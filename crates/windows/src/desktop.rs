use crate::{
    Error, WindowOwner, can_request_graceful_close, finish_foreground_snapshot, sample_applications,
};
use desktop_applications::{
    ApplicationIdentifier, ApplicationSnapshot, IdentifierKind, ProcessIdentity, validate_target,
};
use std::path::Path;
use windows_sys::Win32::{Foundation::*, System::Threading::*, UI::WindowsAndMessaging::*};

struct Process(HANDLE);
impl Drop for Process {
    fn drop(&mut self) {
        unsafe {
            CloseHandle(self.0);
        }
    }
}

impl Process {
    fn open(pid: u32, terminate: bool) -> Result<Self, Error> {
        if pid == 0 {
            return Err(Error::InvalidInput);
        }
        let rights = PROCESS_QUERY_LIMITED_INFORMATION
            | PROCESS_SYNCHRONIZE
            | if terminate { PROCESS_TERMINATE } else { 0 };
        let handle = unsafe { OpenProcess(rights, 0, pid) };
        if handle.is_null() {
            let code = unsafe { GetLastError() };
            return Err(if code == ERROR_INVALID_PARAMETER {
                Error::Unavailable
            } else {
                Error::Native(code)
            });
        }
        Ok(Self(handle))
    }

    fn is_terminated(&self) -> Result<bool, Error> {
        match unsafe { WaitForSingleObject(self.0, 0) } {
            WAIT_OBJECT_0 => Ok(true),
            WAIT_TIMEOUT => Ok(false),
            _ => Err(Error::Native(unsafe { GetLastError() })),
        }
    }

    fn snapshot(&self, pid: u32) -> Result<ApplicationSnapshot, Error> {
        let mut creation = FILETIME::default();
        let mut exit = FILETIME::default();
        let mut kernel = FILETIME::default();
        let mut user = FILETIME::default();
        if unsafe { GetProcessTimes(self.0, &mut creation, &mut exit, &mut kernel, &mut user) } == 0
        {
            return Err(Error::Native(unsafe { GetLastError() }));
        }
        let terminated = self.is_terminated()?;
        let mut path = vec![0u16; 32768];
        let mut length = path.len() as u32;
        if unsafe { QueryFullProcessImageNameW(self.0, 0, path.as_mut_ptr(), &mut length) } == 0 {
            return Err(Error::Native(unsafe { GetLastError() }));
        }
        let path = String::from_utf16(&path[..length as usize]).map_err(|_| Error::InvalidInput)?;
        let display_name = Path::new(&path)
            .file_stem()
            .and_then(|s| s.to_str())
            .map(str::to_owned);
        Ok(ApplicationSnapshot {
            identity: ProcessIdentity {
                process_id: pid,
                start_time: ((creation.dwHighDateTime as u64) << 32)
                    | creation.dwLowDateTime as u64,
            },
            identifier: Some(ApplicationIdentifier {
                kind: IdentifierKind::Executable,
                value: path,
            }),
            display_name,
            terminated,
        })
    }
}

pub fn application(pid: u32) -> Result<ApplicationSnapshot, Error> {
    Process::open(pid, false)?.snapshot(pid)
}

struct OwnedWindow {
    hwnd: HWND,
    owner: WindowOwner,
}

fn window_owner(hwnd: HWND) -> Option<WindowOwner> {
    let mut pid = 0;
    let thread = unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
    (pid != 0 && thread != 0).then_some(WindowOwner {
        process_id: pid,
        thread_id: thread,
    })
}

unsafe extern "system" fn collect_window(hwnd: HWND, context: LPARAM) -> i32 {
    let windows = unsafe { &mut *(context as *mut Vec<OwnedWindow>) };
    if unsafe { IsWindowVisible(hwnd) } != 0
        && unsafe { GetWindow(hwnd, GW_OWNER) }.is_null()
        && let Some(owner) = window_owner(hwnd)
    {
        windows.push(OwnedWindow { hwnd, owner });
    }
    1
}

fn windows() -> Result<Vec<OwnedWindow>, Error> {
    let mut result: Vec<OwnedWindow> = Vec::new();
    if unsafe { EnumWindows(Some(collect_window), &mut result as *mut _ as LPARAM) } == 0 {
        return Err(Error::Native(unsafe { GetLastError() }));
    }
    Ok(result)
}

/// Enumerates applications owning visible unowned top-level windows. Services,
/// background-only processes and inaccessible processes are intentionally absent.
pub fn running_applications() -> Result<Vec<ApplicationSnapshot>, Error> {
    Ok(sample_applications(
        windows()?.into_iter().map(|window| window.owner.process_id),
        application,
    ))
}

fn foreground_process_id() -> Option<u32> {
    let hwnd = unsafe { GetForegroundWindow() };
    if hwnd.is_null() {
        return None;
    }
    window_owner(hwnd).map(|owner| owner.process_id)
}

/// Sample the foreground app while the same live process owns the foreground.
pub fn foreground_application() -> Result<ApplicationSnapshot, Error> {
    let pid = foreground_process_id().ok_or(Error::Unavailable)?;
    let process = Process::open(pid, false)?;
    let snapshot = process.snapshot(pid)?;
    // The retained handle distinguishes an exited process from later PID reuse.
    finish_foreground_snapshot(snapshot, foreground_process_id, || process.is_terminated())
}

/// The process handle is retained for validation and the requested operation.
fn checked(target: &ApplicationSnapshot, terminate: bool) -> Result<Process, Error> {
    let process = Process::open(target.identity.process_id, terminate)?;
    let current = process.snapshot(target.identity.process_id)?;
    validate_target(target, &current).map_err(|_| Error::TargetChanged)?;
    Ok(process)
}

pub fn activate(target: &ApplicationSnapshot) -> Result<(), Error> {
    let process = checked(target, false)?;
    let window = windows()?
        .into_iter()
        .find(|window| window.owner.process_id == target.identity.process_id)
        .ok_or(Error::Unavailable)?;
    validate_target(target, &process.snapshot(target.identity.process_id)?)
        .map_err(|_| Error::TargetChanged)?;
    window.owner.request(
        || window_owner(window.hwnd),
        || {
            if unsafe { SetForegroundWindow(window.hwnd) } == 0 {
                return Err(Error::RequestRejected);
            }
            Ok(())
        },
    )
}

/// Graceful termination queues WM_CLOSE for the application's visible root
/// windows. The application may refuse, prompt to save, or keep running.
pub fn terminate(target: &ApplicationSnapshot, force: bool) -> Result<(), Error> {
    if target.identity.process_id == unsafe { GetCurrentProcessId() } {
        return Err(Error::InvalidInput);
    }
    let process = checked(target, force)?;
    if force {
        if unsafe { TerminateProcess(process.0, 1) } == 0 {
            return Err(Error::Native(unsafe { GetLastError() }));
        }
    } else {
        let targets: Vec<_> = windows()?
            .into_iter()
            .filter(|window| window.owner.process_id == target.identity.process_id)
            .collect();
        if targets.is_empty() {
            return Err(Error::Unavailable);
        }
        for window in targets {
            if !can_request_graceful_close(
                target,
                process.snapshot(target.identity.process_id),
                || process.is_terminated(),
            )? {
                return Ok(());
            }
            window.owner.request(
                || window_owner(window.hwnd),
                || {
                    if unsafe { PostMessageW(window.hwnd, WM_CLOSE, 0, 0) } == 0 {
                        return Err(Error::Native(unsafe { GetLastError() }));
                    }
                    Ok(())
                },
            )?;
        }
    }
    Ok(())
}

/// Launches an explicit executable directly without a shell or PATH lookup.
pub fn launch(executable: &str, arguments: &[String]) -> Result<u32, Error> {
    let path = Path::new(executable);
    if !path.is_absolute()
        || !path
            .extension()
            .is_some_and(|s| s.eq_ignore_ascii_case("exe"))
        || executable.encode_utf16().any(|c| c == 0)
        || arguments.iter().any(|s| s.contains('\0'))
    {
        return Err(Error::InvalidInput);
    }
    match path.metadata() {
        Ok(metadata) if metadata.is_file() => {}
        Ok(_) => return Err(Error::InvalidInput),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(Error::Unavailable);
        }
        Err(error) => return Err(Error::Native(error.raw_os_error().unwrap_or(0) as u32)),
    }
    let child = std::process::Command::new(path)
        .args(arguments)
        .spawn()
        .map_err(|e| Error::Native(e.raw_os_error().unwrap_or(0) as u32))?;
    Ok(child.id())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_distinguishes_invalid_input_from_missing_executable() {
        assert_eq!(launch("relative.exe", &[]), Err(Error::InvalidInput));
        let missing = std::env::temp_dir()
            .join(format!("desktop-applications-{}-missing.exe", unsafe {
                GetCurrentProcessId()
            }));
        assert!(!missing.exists());
        assert_eq!(
            launch(missing.to_str().unwrap(), &[]),
            Err(Error::Unavailable)
        );
    }

    #[test]
    fn process_query_can_inspect_creation_and_exit_state_of_the_current_process() {
        let process_id = unsafe { GetCurrentProcessId() };
        let snapshot = application(process_id).expect("query the owned test process");
        assert_eq!(snapshot.identity.process_id, process_id);
        assert!(snapshot.identity.start_time > 0);
        assert!(!snapshot.terminated);
        assert_eq!(
            snapshot.identifier.unwrap().kind,
            IdentifierKind::Executable
        );
    }
}
