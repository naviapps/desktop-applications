use crate::receipt::{Receipt, WindowState};
use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::ptr::{null, null_mut};
use std::{fs, io};

use windows_sys::{
    Win32::{
        Foundation::{HWND, LPARAM, LRESULT, WPARAM},
        System::LibraryLoader::GetModuleHandleW,
        UI::WindowsAndMessaging::*,
    },
    w,
};

const READY_TIMER: usize = 1;
const CLASS: *const u16 = w!("DesktopApplications.OwnedTarget");

struct Desktop {
    destination: PathBuf,
    receipt: RefCell<Receipt>,
    first: Cell<HWND>,
    second: Cell<HWND>,
    write_error: RefCell<Option<io::Error>>,
}

impl Desktop {
    fn windows(&self) -> [WindowState; 2] {
        [self.first.get(), self.second.get()].map(|handle| {
            if handle.is_null() || unsafe { IsWindow(handle) } == 0 {
                return WindowState::default();
            }
            WindowState {
                handle: handle as isize as i64,
                visible: unsafe { IsWindowVisible(handle) } != 0,
                owner: unsafe { GetWindow(handle, GW_OWNER) } as isize as i64,
            }
        })
    }

    fn record(&self, windows: [WindowState; 2]) {
        if let Err(error) = fs::write(
            &self.destination,
            self.receipt.borrow().json(windows).to_string(),
        ) {
            self.write_error.replace(Some(error));
            unsafe { PostQuitMessage(1) };
        }
    }

    fn create(&self, title: *const u16, width: i32, height: i32) -> io::Result<HWND> {
        let window = unsafe {
            CreateWindowExW(
                0,
                CLASS,
                title,
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                width,
                height,
                null_mut(),
                null_mut(),
                GetModuleHandleW(null()),
                std::ptr::from_ref(self).cast(),
            )
        };
        if window.is_null() {
            Err(io::Error::last_os_error())
        } else {
            Ok(window)
        }
    }

    fn message_loop(&self) -> io::Result<()> {
        self.first
            .set(self.create(w!("DesktopApplications owned fixture"), 520, 300)?);
        self.second
            .set(self.create(w!("DesktopApplications owned second window"), 400, 250)?);
        unsafe {
            ShowWindow(self.first.get(), SW_SHOW);
            ShowWindow(self.second.get(), SW_SHOW);
        }
        if unsafe { SetTimer(self.first.get(), READY_TIMER, 50, None) } == 0 {
            return Err(io::Error::last_os_error());
        }
        let mut message = MSG::default();
        loop {
            match unsafe { GetMessageW(&raw mut message, null_mut(), 0, 0) } {
                -1 => return Err(io::Error::last_os_error()),
                0 => return self.write_error.take().map_or(Ok(()), Err),
                _ => unsafe {
                    TranslateMessage(&raw const message);
                    DispatchMessageW(&raw const message);
                },
            }
        }
    }
}

unsafe extern "system" fn window_proc(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == WM_NCCREATE {
        let input = unsafe { &*(lparam as *const CREATESTRUCTW) };
        unsafe { SetWindowLongPtrW(window, GWLP_USERDATA, input.lpCreateParams as isize) };
    }
    let desktop = unsafe { (GetWindowLongPtrW(window, GWLP_USERDATA) as *const Desktop).as_ref() };
    if let Some(desktop) = desktop {
        match message {
            WM_TIMER if window == desktop.first.get() && wparam == READY_TIMER => {
                // Report readiness only from a serviced timer on the owned UI thread.
                let windows = desktop.windows();
                desktop.receipt.borrow_mut().timer(windows);
                desktop.record(windows);
                if desktop.receipt.borrow().ready {
                    unsafe { KillTimer(window, READY_TIMER) };
                }
                return 0;
            }
            WM_CLOSE => {
                let refuse = desktop.receipt.borrow_mut().close_request();
                desktop.record(desktop.windows());
                if refuse {
                    return 0;
                }
            }
            WM_DESTROY if window == desktop.first.get() => unsafe { PostQuitMessage(0) },
            _ => {}
        }
    }
    unsafe { DefWindowProcW(window, message, wparam, lparam) }
}

pub fn run(destination: PathBuf, refuse_close: bool) -> io::Result<()> {
    let receipt = Receipt::new(refuse_close);
    fs::write(&destination, receipt.starting().to_string())?;
    let class = WNDCLASSW {
        lpfnWndProc: Some(window_proc),
        hInstance: unsafe { GetModuleHandleW(null()) },
        hCursor: unsafe { LoadCursorW(null_mut(), IDC_ARROW) },
        lpszClassName: CLASS,
        ..WNDCLASSW::default()
    };
    if unsafe { RegisterClassW(&raw const class) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let desktop = Desktop {
        destination,
        receipt: RefCell::new(receipt),
        first: Cell::new(null_mut()),
        second: Cell::new(null_mut()),
        write_error: RefCell::new(None),
    };
    let result = desktop.message_loop();
    for window in [desktop.second.get(), desktop.first.get()] {
        if !window.is_null() && unsafe { IsWindow(window) } != 0 {
            unsafe { DestroyWindow(window) };
        }
    }
    result
}
