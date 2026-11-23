//! Owned JSON results keep foreign ownership and failure handling explicit.
use desktop_applications::{
    ApplicationEventSelector, ApplicationIdentifier, ApplicationSnapshot, ApplicationState,
    Lifecycle,
};
use serde::Deserialize;
mod resource_cache;
pub use resource_cache::*;

#[cfg(test)]
mod transport_tests;

pub struct Buffer(Vec<u8>);

pub const DESKTOP_APPLICATIONS_ABI_VERSION: u32 = 2u32;

#[unsafe(no_mangle)]
pub extern "C" fn desktop_applications_abi_version() -> u32 {
    DESKTOP_APPLICATIONS_ABI_VERSION
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Target {
    expected: ApplicationSnapshot,
    actual: ApplicationSnapshot,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Reconciliation {
    previous: ApplicationState,
    current: ApplicationState,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EventIdentity {
    lifecycle: Lifecycle,
    identifier: Option<ApplicationIdentifier>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EventSelection {
    lifecycles: Vec<Lifecycle>,
    identifier: Option<ApplicationIdentifier>,
    candidates: Vec<EventIdentity>,
}

fn query(operation: u32, input: &[u8]) -> Result<serde_json::Value, String> {
    match operation {
        1 => {
            let id: ApplicationIdentifier =
                serde_json::from_slice(input).map_err(|e| e.to_string())?;
            id.normalized()
                .map(|id| serde_json::json!(id))
                .map_err(|e| format!("{e:?}"))
        }
        2 => {
            let target: Target = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            Ok(serde_json::json!(
                desktop_applications::validate_target(&target.expected, &target.actual).err()
            ))
        }
        3 => {
            let change: Reconciliation =
                serde_json::from_slice(input).map_err(|e| e.to_string())?;
            let (state, events) = change
                .previous
                .reconcile(&change.current)
                .map_err(|e| format!("{e:?}"))?;
            Ok(serde_json::json!({"state":state,"events":events}))
        }
        4 => {
            let input: EventSelection = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            let selector =
                ApplicationEventSelector::new(&input.lifecycles, input.identifier.as_ref())
                    .map_err(|error| format!("{error:?}"))?;
            let matching: Vec<_> = input
                .candidates
                .iter()
                .enumerate()
                .filter_map(|(index, item)| {
                    selector
                        .matches(item.lifecycle, item.identifier.as_ref())
                        .then_some(index)
                })
                .collect();
            Ok(serde_json::json!(matching))
        }
        10..=16 => windows_query(operation, input),
        _ => Err("Unknown operation".into()),
    }
}

#[cfg(not(windows))]
fn windows_query(_: u32, _: &[u8]) -> Result<serde_json::Value, String> {
    Err("Native Windows operations require Windows".into())
}

#[cfg(windows)]
fn windows_query(operation: u32, input: &[u8]) -> Result<serde_json::Value, String> {
    use desktop_applications_windows as native;
    fn result<T: serde::Serialize>(value: Result<T, native::Error>) -> serde_json::Value {
        match value {
            Ok(value) => serde_json::json!({"result":value}),
            Err(error) => serde_json::json!({"failure":error}),
        }
    }
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Empty {}
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct Process {
        process_id: u32,
    }
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Launch {
        executable: String,
        arguments: Vec<String>,
    }
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Control {
        target: ApplicationSnapshot,
        force: bool,
    }
    match operation {
        10 | 11 | 16 => {
            let _: Empty = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            Ok(match operation {
                10 => result(native::running_applications()),
                11 => result(native::foreground_application()),
                _ => result(native::running_applications().map(|applications| {
                    let frontmost = native::foreground_application()
                        .ok()
                        .map(|s| s.identity)
                        .filter(|id| applications.iter().any(|s| s.identity == *id));
                    ApplicationState {
                        applications,
                        frontmost,
                    }
                })),
            })
        }
        12 => {
            let process: Process = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            Ok(result(native::application(process.process_id)))
        }
        13 => {
            let launch: Launch = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            Ok(result(native::launch(
                &launch.executable,
                &launch.arguments,
            )))
        }
        14 | 15 => {
            let control: Control = serde_json::from_slice(input).map_err(|e| e.to_string())?;
            Ok(result(if operation == 14 {
                native::activate(&control.target)
            } else {
                native::terminate(&control.target, control.force)
            }))
        }
        _ => Err("Unknown Windows operation".into()),
    }
}

fn response(result: Result<serde_json::Value, String>) -> *mut Buffer {
    let value = match result {
        Ok(value) => serde_json::json!({"value":value}),
        Err(error) => serde_json::json!({"error":error}),
    };
    Box::into_raw(Box::new(Buffer(
        serde_json::to_vec(&value).expect("serializable response"),
    )))
}

/// Operations: identifier normalization (1), recorded-target validation (2),
/// lifecycle reconciliation (3), matching lifecycle event indices (4).
/// Operation 4 accepts lifecycles, an optional identifier and ordered candidates
/// with lifecycle and optional identifier. Windows operations: running apps (10),
/// foreground app (11), process query (12), executable launch (13), activation
/// (14), termination (15) and observation snapshot (16).
///
/// Input is UTF-8 JSON, at most 8 MiB. The owned result contains either `value`
/// or `error`. Null indicates null/oversized input or a caught panic.
///
/// # Safety
/// Input must address `length` readable bytes for the call. Release the result
/// exactly once after copying any borrowed bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn desktop_applications_query(
    operation: u32,
    input: *const u8,
    length: usize,
) -> *mut Buffer {
    if input.is_null() || length > 8 * 1024 * 1024 {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let input = unsafe { std::slice::from_raw_parts(input, length) };
        response(query(operation, input))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `buffer` must be null or a live result returned by this library. If `length`
/// is nonnull and aligned, it must be writable. Copy borrowed bytes before
/// releasing the result.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn desktop_applications_buffer_data(
    buffer: *const Buffer,
    length: *mut usize,
) -> *const u8 {
    if length.is_null() || !length.is_aligned() {
        return std::ptr::null();
    }
    unsafe {
        *length = 0;
    }
    let Some(buffer) = (unsafe { buffer.as_ref() }) else {
        return std::ptr::null();
    };
    unsafe {
        *length = buffer.0.len();
    }
    buffer.0.as_ptr()
}

/// # Safety
/// A nonnull pointer must be a live result returned by this library, released
/// exactly once. Null is accepted.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn desktop_applications_buffer_free(buffer: *mut Buffer) {
    if !buffer.is_null() {
        drop(unsafe { Box::from_raw(buffer) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_input_is_a_failure_not_a_panic() {
        assert!(query(1, br#"{"kind":"bundle","value":"a","value":"b"}"#).is_err());
        assert!(query(1, br#"{"kind":"bundle","value":"a","extra":0}"#).is_err());
        assert!(query(99, b"{}").is_err());
        unsafe {
            assert!(desktop_applications_query(1, std::ptr::null(), 1).is_null());
            let mut size = 9;
            assert!(desktop_applications_buffer_data(std::ptr::null(), &mut size).is_null());
            assert_eq!(size, 0);
            desktop_applications_buffer_free(std::ptr::null_mut());
        }
    }
}
