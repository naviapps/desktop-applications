// This library ships as a staticlib/cdylib without an rlib for Cargo integration tests.
// Compile its source as an ordinary module to call the existing ABI from this harness.
#[path = "../src/lib.rs"]
mod ffi;

use ffi::*;
use serde_json::{Value, json};
use std::ptr::{null, null_mut};

const INPUT_LIMIT: usize = 8 * 1024 * 1024;

struct OwnedBuffer(*mut Buffer);

impl OwnedBuffer {
    fn new(raw: *mut Buffer) -> Self {
        assert!(!raw.is_null());
        Self(raw)
    }

    fn bytes(&self) -> &[u8] {
        let mut length = 0;
        // The view borrows from the live owner, with the same lifetime as this borrow.
        let data = unsafe { desktop_applications_buffer_data(self.0, &mut length) };
        assert!(!data.is_null() && length > 0);
        unsafe { std::slice::from_raw_parts(data, length) }
    }

    fn json(&self) -> Value {
        serde_json::from_slice(self.bytes()).unwrap()
    }
}

impl Drop for OwnedBuffer {
    fn drop(&mut self) {
        unsafe { desktop_applications_buffer_free(self.0) }
    }
}

fn verify_admission(
    call: impl Fn(*const u8, usize) -> *mut Buffer,
    request: &[u8],
    expected: &Value,
) -> OwnedBuffer {
    // All nonnull lengths, including the rejected one, address allocated input.
    let mut input = vec![b' '; INPUT_LIMIT + 1];
    input[..request.len()].copy_from_slice(request);
    assert!(call(null(), 0).is_null());
    assert!(call(null(), 1).is_null());
    assert!(call(input.as_ptr(), input.len()).is_null());

    let exact_limit = OwnedBuffer::new(call(input.as_ptr(), INPUT_LIMIT));
    let small = OwnedBuffer::new(call(input.as_ptr(), request.len()));
    assert_eq!(exact_limit.json(), *expected);
    assert_eq!(exact_limit.bytes(), small.bytes());
    drop(small);

    let empty = OwnedBuffer::new(call(input.as_ptr(), 0));
    let failure = empty.json();
    let failure = failure.as_object().unwrap();
    assert_eq!(failure.len(), 1);
    assert!(
        failure["error"]
            .as_str()
            .is_some_and(|text| !text.is_empty())
    );
    assert_ne!(empty.0, exact_limit.0);
    drop(empty);
    assert_eq!(exact_limit.json(), *expected);
    exact_limit
}

#[test]
fn input_admission_and_result_ownership_match_across_both_endpoints() {
    let selection_value = json!({"value": []});
    let selection = verify_admission(
        |input, length| unsafe { desktop_applications_query(4, input, length) },
        br#"{"lifecycles":[],"candidates":[]}"#,
        &selection_value,
    );
    let cache = desktop_applications_resource_cache_create();
    assert!(!cache.is_null());
    let resource_value =
        json!({"value": {"evictedGenerations": [], "generation": null, "loadIsCurrent": false}});
    let resource = verify_admission(
        |input, length| unsafe { desktop_applications_resource_cache_query(cache, input, length) },
        br#"{"action":"validateLoad","generation":0}"#,
        &resource_value,
    );
    // A cache query owns its response separately from both the cache and other queries.
    unsafe { desktop_applications_resource_cache_destroy(cache) };
    assert_ne!(selection.0, resource.0);
    assert_eq!(selection.json(), selection_value);
    drop(selection);
    assert_eq!(resource.json(), resource_value);
    unsafe {
        assert!(desktop_applications_buffer_data(resource.0, null_mut()).is_null());
        let mut length = 17;
        assert!(desktop_applications_buffer_data(null(), &mut length).is_null());
        assert_eq!(length, 0);
        desktop_applications_buffer_free(null_mut());
    }
}

#[test]
fn reconciliation_preserves_the_complete_sample_and_ordered_events_over_the_abi() {
    let reconcile = |previous: &Value, current: &Value| {
        let request = json!({"previous": previous, "current": current}).to_string();
        OwnedBuffer::new(unsafe { desktop_applications_query(3, request.as_ptr(), request.len()) })
            .json()
    };
    let original = json!({
        "identity": {"processId": 40, "startTime": 100},
        "identifier": {"kind": "bundle", "value": "com.example.app"},
        "displayName": "Caf\u{e9}",
        "terminated": false,
    });
    let mut replacement = original.clone();
    replacement["identity"]["startTime"] = json!(u64::MAX);
    replacement["displayName"] = json!("Cafe\u{301}");
    let sample = |application: &Value| json!({"applications": [application], "frontmost": application["identity"]});
    let previous = sample(&original);
    let current = sample(&replacement);
    let mut terminated = original.clone();
    terminated["terminated"] = json!(true);
    let result = reconcile(&previous, &current);
    assert_eq!(
        result,
        json!({"value": {"state": current, "events": [
            {"lifecycle": "deactivated", "application": original},
            {"lifecycle": "terminated", "application": terminated},
            {"lifecycle": "launched", "application": replacement},
            {"lifecycle": "activated", "application": replacement},
        ]}})
    );
    assert_eq!(reconcile(&previous, &current), result);
    assert_eq!(
        reconcile(&result["value"]["state"], &current),
        json!({"value": {"state": current, "events": []}})
    );

    let mut unavailable = previous.clone();
    unavailable["applications"][0]["identity"]["startTime"] = json!(0);
    for (before, after) in [(&unavailable, &current), (&previous, &unavailable)] {
        assert_eq!(
            reconcile(before, after),
            json!({"error": "IdentityUnavailable"})
        );
    }
    let mut stale_foreground = current.clone();
    stale_foreground["frontmost"] = previous["frontmost"].clone();
    assert_eq!(
        reconcile(&previous, &stale_foreground),
        json!({"error": "TargetChanged"})
    );
}
