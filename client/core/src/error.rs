use std::fmt;

/// Why an operation failed. The user interface reacts to the first four codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    /// The addon folder exists, but the manager did not install it.
    Unmanaged,
    /// The addon folder is a link to a development copy.
    Linked,
    /// The package or the marketplace index is not acceptable.
    InvalidPackage,
    /// The addon is not installed.
    NotInstalled,
    Other,
}

#[derive(Debug)]
pub struct Error {
    pub code: ErrorCode,
    pub message: String,
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    pub fn other(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Other, message)
    }

    /// Name of the code for the user interface, or `None` for a plain error.
    pub fn code_name(&self) -> Option<&'static str> {
        match self.code {
            ErrorCode::Unmanaged => Some("UNMANAGED"),
            ErrorCode::Linked => Some("LINKED"),
            ErrorCode::InvalidPackage => Some("INVALID_PACKAGE"),
            ErrorCode::NotInstalled => Some("NOT_INSTALLED"),
            ErrorCode::Other => None,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Self::other(error.to_string())
    }
}

impl From<serde_json::Error> for Error {
    fn from(error: serde_json::Error) -> Self {
        Self::other(error.to_string())
    }
}
