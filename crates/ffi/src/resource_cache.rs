use desktop_applications::{ApplicationResourceCache, ApplicationResourceCacheAction};
use std::sync::Mutex;

pub struct ResourceCache(Mutex<ApplicationResourceCache>);

fn apply(cache: &ResourceCache, input: &[u8]) -> Result<serde_json::Value, String> {
    let action: ApplicationResourceCacheAction =
        serde_json::from_slice(input).map_err(|e| e.to_string())?;
    let mut cache = cache.0.lock().unwrap_or_else(|error| error.into_inner());
    let transition = cache.apply(action).map_err(|error| format!("{error:?}"))?;
    Ok(serde_json::json!(transition))
}

/// Creates an independent cache; no native values or callbacks enter Rust.
///
/// The cache owns bounded resource identities and load generations.
#[unsafe(no_mangle)]
pub extern "C" fn desktop_applications_resource_cache_create() -> *mut ResourceCache {
    Box::into_raw(Box::new(ResourceCache(Mutex::new(
        ApplicationResourceCache::default(),
    ))))
}

/// Resolves resources, validates or admits load generations, or invalidates by
/// optional identifier (`resolve`, `validateLoad`, `admitLoad`, `invalidate`).
/// A response reports only `generation`, `evictedGenerations` and `loadIsCurrent`.
/// Detach evicted values before releasing them, since destructors may reenter the
/// cache. Retain loads once `admitLoad` confirms their generation. Missing values
/// are never admitted, and ready hits reuse their generation.
///
/// # Safety
/// Owner stays live; input addresses length immutable readable bytes for this call.
/// The owned result uses the ordinary buffer view/free API. Null/oversized input
/// is rejected before mutation. No caller callback runs under the native lock.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn desktop_applications_resource_cache_query(
    owner: *const ResourceCache,
    input: *const u8,
    length: usize,
) -> *mut super::Buffer {
    if input.is_null() || length > 8 * 1024 * 1024 {
        return std::ptr::null_mut();
    }
    let Some(cache) = (unsafe { owner.as_ref() }) else {
        return std::ptr::null_mut();
    };
    std::panic::catch_unwind(|| {
        super::response(apply(cache, unsafe {
            std::slice::from_raw_parts(input, length)
        }))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// Owner is null or exclusively owned, with no live/concurrent calls.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn desktop_applications_resource_cache_destroy(owner: *mut ResourceCache) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owned_cache_retains_state_and_returns_only_tokens_and_eviction_deltas() {
        let cache = ResourceCache(Mutex::new(ApplicationResourceCache::default()));
        let request = br#"{"action":"resolve","resource":{"identifier":{"kind":"bundle","value":"com.example.app"},"location":"/app","revision":"1","variant":"icon"}}"#;
        let first = apply(&cache, request).unwrap();
        assert_eq!(first["generation"], 1);
        let second = apply(&cache, request).unwrap();
        assert_eq!(second["generation"], 2);
        assert_eq!(second["evictedGenerations"], serde_json::json!([1]));
        assert!(!apply(&cache, br#"{"action":"validateLoad","generation":1}"#).unwrap()["loadIsCurrent"].as_bool().unwrap());
        assert!(
            apply(&cache, br#"{"action":"validateLoad","generation":2}"#).unwrap()["loadIsCurrent"]
                .as_bool()
                .unwrap()
        );
        assert_eq!(
            apply(&cache, br#"{"action":"invalidate","identifier":null}"#).unwrap()["evictedGenerations"],
            serde_json::json!([2])
        );
        assert!(apply(&cache, br#"{"action":"resolve"}"#).is_err());
        assert!(apply(&cache, br#"{"action":"invalidate","extra":0}"#).is_err());
        unsafe {
            assert!(
                desktop_applications_resource_cache_query(
                    std::ptr::null(),
                    request.as_ptr(),
                    request.len()
                )
                .is_null()
            );
            assert!(
                desktop_applications_resource_cache_query(&cache, std::ptr::null(), 1).is_null()
            );
            desktop_applications_resource_cache_destroy(std::ptr::null_mut());
        }
    }
}
