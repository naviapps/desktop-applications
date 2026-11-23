use serde_json::{Value, json};

#[derive(Clone, Copy, Default)]
pub struct WindowState {
    pub handle: i64,
    pub visible: bool,
    pub owner: i64,
}

impl WindowState {
    fn eligible(self) -> bool {
        self.handle != 0 && self.visible && self.owner == 0
    }

    fn json(self) -> Value {
        json!({ "handle": self.handle, "visible": self.visible, "owner": self.owner })
    }
}

pub struct Receipt {
    pub ready: bool,
    refuse_close: bool,
    close_requests: u32,
}

impl Receipt {
    pub fn new(refuse_close: bool) -> Self {
        Self {
            ready: false,
            refuse_close,
            close_requests: 0,
        }
    }

    pub fn starting(&self) -> Value {
        json!({ "processId": std::process::id(), "stage": "starting", "closeRequests": 0 })
    }

    pub fn timer(&mut self, windows: [WindowState; 2]) {
        self.ready = windows.iter().all(|window| window.eligible())
            && windows[0].handle != windows[1].handle;
    }

    pub fn close_request(&mut self) -> bool {
        self.close_requests = self.close_requests.saturating_add(1);
        self.refuse_close
    }

    pub fn json(&self, windows: [WindowState; 2]) -> Value {
        json!({
            "processId": std::process::id(),
            "ready": self.ready,
            "closeRequests": self.close_requests,
            "refuseClose": self.refuse_close,
            "windows": windows.map(WindowState::json),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIRST: WindowState = WindowState {
        handle: 42,
        visible: true,
        owner: 0,
    };
    const SECOND: WindowState = WindowState {
        handle: 43,
        visible: true,
        owner: 0,
    };

    #[test]
    fn readiness_requires_the_timer_and_two_distinct_unowned_visible_handles() {
        let mut receipt = Receipt::new(false);
        assert_eq!(
            receipt.starting(),
            json!({"processId": std::process::id(), "stage": "starting", "closeRequests": 0}),
        );
        assert_eq!(receipt.json([FIRST, SECOND])["ready"], false);
        for invalid in [
            WindowState::default(),
            WindowState {
                visible: false,
                ..SECOND
            },
            WindowState {
                owner: 42,
                ..SECOND
            },
            FIRST,
        ] {
            receipt.timer([FIRST, invalid]);
            assert!(!receipt.ready);
        }
        receipt.timer([FIRST, SECOND]);
        assert!(receipt.ready);
    }

    #[test]
    fn close_observations_keep_the_process_identity_and_count_each_delivery() {
        let mut receipt = Receipt::new(true);
        receipt.timer([FIRST, SECOND]);
        assert!(receipt.close_request());
        assert_eq!(receipt.json([FIRST, SECOND])["closeRequests"], 1);
        assert!(receipt.close_request());
        assert_eq!(
            receipt.json([FIRST, SECOND]),
            json!({
                "processId": std::process::id(),
                "ready": true,
                "closeRequests": 2,
                "refuseClose": true,
                "windows": [
                    { "handle": 42, "visible": true, "owner": 0 },
                    { "handle": 43, "visible": true, "owner": 0 },
                ],
            }),
        );
        let mut accepting = Receipt::new(false);
        assert!(!accepting.close_request());
        assert_eq!(accepting.json([FIRST, SECOND])["closeRequests"], 1);
    }
}
