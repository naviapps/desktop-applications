//! Native Windows application resources. No product filtering or window geometry.
#[cfg(windows)]
mod desktop;
#[cfg(windows)]
pub use desktop::*;

/// Errors preserve the distinction between unavailable targets, stale identity,
/// foreground-policy rejection and an OS error. No permission is granted here.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Error {
    InvalidInput,
    Unavailable,
    TargetChanged,
    RequestRejected,
    Native(u32),
}

#[cfg(any(windows, test))]
#[derive(Clone, Copy, PartialEq, Eq)]
struct WindowOwner {
    process_id: u32,
    thread_id: u32,
}

#[cfg(any(windows, test))]
impl WindowOwner {
    fn request(
        self,
        read_owner: impl FnOnce() -> Option<Self>,
        operation: impl FnOnce() -> Result<(), Error>,
    ) -> Result<(), Error> {
        if read_owner() != Some(self) {
            return Err(Error::TargetChanged);
        }
        operation()
    }
}

#[cfg(any(windows, test))]
fn sample_applications(
    process_ids: impl IntoIterator<Item = u32>,
    mut read: impl FnMut(u32) -> Result<desktop_applications::ApplicationSnapshot, Error>,
) -> Vec<desktop_applications::ApplicationSnapshot> {
    // One PID can have several windows and can acquire a new creation token
    // during enumeration. Read one generation of each PID for this sample.
    process_ids
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .filter_map(|pid| read(pid).ok())
        .filter(|snapshot| !snapshot.terminated)
        .collect()
}

#[cfg(any(windows, test))]
fn finish_foreground_snapshot(
    snapshot: desktop_applications::ApplicationSnapshot,
    read_foreground_pid: impl FnOnce() -> Option<u32>,
    is_terminated: impl FnOnce() -> Result<bool, Error>,
) -> Result<desktop_applications::ApplicationSnapshot, Error> {
    if snapshot.terminated
        || read_foreground_pid() != Some(snapshot.identity.process_id)
        || is_terminated()?
    {
        return Err(Error::TargetChanged);
    }
    Ok(snapshot)
}

#[cfg(any(windows, test))]
fn can_request_graceful_close(
    target: &desktop_applications::ApplicationSnapshot,
    current: Result<desktop_applications::ApplicationSnapshot, Error>,
    is_terminated: impl FnOnce() -> Result<bool, Error>,
) -> Result<bool, Error> {
    let current = match current {
        Ok(current) => current,
        Err(error) => {
            // A prior close may have exited the process while its metadata was read.
            return if is_terminated() == Ok(true) {
                Ok(false)
            } else {
                Err(error)
            };
        }
    };
    if current.identity == target.identity && current.terminated {
        return Ok(false);
    }
    desktop_applications::validate_target(target, &current).map_err(|_| Error::TargetChanged)?;
    Ok(true)
}

#[cfg(test)]
mod observation_tests {
    use super::*;
    use desktop_applications::{ApplicationSnapshot, ApplicationState, ProcessIdentity};

    fn snapshot(process_id: u32, start_time: u64) -> ApplicationSnapshot {
        ApplicationSnapshot {
            identity: ProcessIdentity {
                process_id,
                start_time,
            },
            identifier: None,
            display_name: None,
            terminated: false,
        }
    }

    #[test]
    fn foreground_snapshot_rejects_a_changed_or_exited_process() {
        let captured = snapshot(20, 100);
        for (foreground, exited) in [(Some(21), false), (None, false), (Some(20), true)] {
            assert_eq!(
                finish_foreground_snapshot(captured.clone(), || foreground, || Ok(exited)),
                Err(Error::TargetChanged)
            );
        }
        assert_eq!(
            finish_foreground_snapshot(
                ApplicationSnapshot {
                    terminated: true,
                    ..captured.clone()
                },
                || Some(20),
                || Ok(true)
            ),
            Err(Error::TargetChanged)
        );
        assert_eq!(
            finish_foreground_snapshot(captured.clone(), || Some(20), || Ok(false)),
            Ok(captured)
        );
    }

    #[test]
    fn repeated_window_owners_never_create_duplicate_pids_in_a_sample() {
        let old = snapshot(20, 100);
        let replacement = snapshot(20, 101);
        let other = snapshot(10, 100);
        let mut reads = 0;
        let applications = sample_applications([20, 10, 20, 30, 40], |pid| match pid {
            10 => Ok(other.clone()),
            20 => {
                reads += 1;
                Ok(if reads == 1 {
                    old.clone()
                } else {
                    replacement.clone()
                })
            }
            30 => Ok(ApplicationSnapshot {
                terminated: true,
                ..snapshot(pid, 100)
            }),
            _ => Err(Error::Unavailable),
        });
        let current = ApplicationState {
            applications,
            frontmost: None,
        };

        // The public managed observer sends each native sample through this validation.
        ApplicationState::default().reconcile(&current).unwrap();
        assert_eq!(reads, 1);
        assert_eq!(current.applications, [other, old]);
    }

    #[test]
    fn graceful_close_stops_when_the_validated_process_exits_during_metadata_read() {
        let target = snapshot(40, 100);
        let failure = Error::Native(6);
        assert_eq!(
            can_request_graceful_close(&target, Err(failure.clone()), || Ok(true)),
            Ok(false)
        );
        assert_eq!(
            can_request_graceful_close(&target, Err(failure.clone()), || Ok(false)),
            Err(failure.clone())
        );
        assert_eq!(
            can_request_graceful_close(&target, Err(failure.clone()), || Err(Error::Native(5))),
            Err(failure)
        );
        assert_eq!(
            can_request_graceful_close(&target, Ok(target.clone()), || panic!(
                "unneeded exit probe"
            )),
            Ok(true)
        );
        let exited = ApplicationSnapshot {
            terminated: true,
            ..target.clone()
        };
        assert_eq!(
            can_request_graceful_close(&target, Ok(exited), || panic!("unneeded exit probe")),
            Ok(false)
        );
        assert_eq!(
            can_request_graceful_close(&target, Ok(snapshot(40, 101)), || panic!(
                "unneeded exit probe"
            )),
            Err(Error::TargetChanged)
        );
    }
}

#[cfg(test)]
mod window_owner_tests {
    use super::*;

    #[test]
    fn vanished_or_reassigned_window_never_reaches_the_requested_effect() {
        let recorded = WindowOwner {
            process_id: 20,
            thread_id: 30,
        };
        for actual in [
            None,
            Some(WindowOwner {
                process_id: 21,
                ..recorded
            }),
            Some(WindowOwner {
                thread_id: 31,
                ..recorded
            }),
        ] {
            let mut requested = false;
            let result = recorded.request(
                || actual,
                || {
                    requested = true;
                    Ok(())
                },
            );
            assert_eq!(result, Err(Error::TargetChanged));
            assert!(!requested);
        }
        assert_eq!(
            recorded.request(|| Some(recorded), || Err(Error::RequestRejected)),
            Err(Error::RequestRejected)
        );
    }
}
