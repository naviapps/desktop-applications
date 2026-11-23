#![cfg_attr(all(windows, not(test)), windows_subsystem = "windows")]

#[cfg(all(not(test), not(all(windows, target_arch = "x86_64"))))]
compile_error!("The owned application fixture requires a Windows x64 target.");

#[cfg(any(windows, test))]
mod receipt;

#[cfg(windows)]
mod desktop;

#[cfg(windows)]
fn main() -> std::io::Result<()> {
    let mut args = std::env::args_os().skip(1);
    let (Some(receipt), Some(mode), None) = (args.next(), args.next(), args.next()) else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Expected an owned receipt path and close mode.",
        ));
    };
    desktop::run(receipt.into(), mode == "refuse")
}
