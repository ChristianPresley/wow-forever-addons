//! Core of the Forever Addon Manager: it finds World of Warcraft: Forever installs,
//! reads the marketplace, and installs, updates and removes addons.
//!
//! The desktop app (`src-tauri`) and the `wfam` command line both use this crate.

pub mod addons;
pub mod detect;
pub mod error;
pub mod marketplace;
pub mod service;
pub mod toc;
pub mod version;

pub use error::{Error, ErrorCode, Result};
