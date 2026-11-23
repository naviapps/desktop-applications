//! Application identity and deterministic lifecycle reconciliation.
//! OS handles, application selection policy and window control are adapter concerns.
mod resources;
pub use resources::*;

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, btree_map::Entry};

/// Identifiers are opaque OS lookup keys, not portable cross-machine identities.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum IdentifierKind {
    Bundle,
    Executable,
    AppUserModel,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ApplicationIdentifier {
    pub kind: IdentifierKind,
    pub value: String,
}

impl ApplicationIdentifier {
    /// Bundle lookup accepts surrounding Unicode whitespace. Paths and Windows
    /// lookup keys retain their exact spelling. No identifier is case folded.
    pub fn normalized(&self) -> Result<Self, ValidationError> {
        Ok(Self {
            kind: self.kind,
            value: self.normalized_value()?.into(),
        })
    }

    fn normalized_value(&self) -> Result<&str, ValidationError> {
        let value = match self.kind {
            IdentifierKind::Bundle => self.value.trim(),
            _ => &self.value,
        };
        if value.is_empty() || value.chars().any(char::is_control) {
            return Err(ValidationError::InvalidIdentifier);
        }
        Ok(value)
    }
}

/// Start time is an opaque, nonzero platform-native process creation token.
/// It is compared only on the same machine and platform, never across OSes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProcessIdentity {
    pub process_id: u32,
    pub start_time: u64,
}

impl ProcessIdentity {
    pub fn validate(self) -> Result<Self, ValidationError> {
        if self.process_id == 0 {
            Err(ValidationError::InvalidProcessId)
        } else if self.start_time == 0 {
            Err(ValidationError::IdentityUnavailable)
        } else {
            Ok(self)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApplicationSnapshot {
    pub identity: ProcessIdentity,
    pub identifier: Option<ApplicationIdentifier>,
    pub display_name: Option<String>,
    pub terminated: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ValidationError {
    InvalidIdentifier,
    InvalidProcessId,
    IdentityUnavailable,
    TargetChanged,
    IdentifierUnavailable,
    IdentifierMismatch,
    Terminated,
    DuplicateProcess,
}

/// Rechecks recorded identity before an OS adapter requests an effect. Adapters
/// must also retain/revalidate their native resource; this check is not atomic
/// with an OS operation and does not turn a PID into a durable process handle.
pub fn validate_target(
    expected: &ApplicationSnapshot,
    actual: &ApplicationSnapshot,
) -> Result<(), ValidationError> {
    if expected.identity.process_id == 0 || actual.identity.process_id == 0 {
        return Err(ValidationError::InvalidProcessId);
    }
    if expected.terminated || actual.terminated {
        return Err(ValidationError::Terminated);
    }
    expected.identity.validate()?;
    actual.identity.validate()?;
    if expected.identity != actual.identity {
        return Err(ValidationError::TargetChanged);
    }
    if let Some(expected_identifier) = &expected.identifier {
        let expected_value = expected_identifier.normalized_value()?;
        let actual_identifier = actual
            .identifier
            .as_ref()
            .ok_or(ValidationError::IdentifierUnavailable)?;
        let actual_value = actual_identifier.normalized_value()?;
        if expected_identifier.kind != actual_identifier.kind || expected_value != actual_value {
            return Err(ValidationError::IdentifierMismatch);
        }
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Lifecycle {
    Launched,
    Terminated,
    Activated,
    Deactivated,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ApplicationEvent {
    pub lifecycle: Lifecycle,
    pub application: ApplicationSnapshot,
}

/// Selects lifecycle events using an optional identifier in its OS namespace.
/// This also matches termination events, whose process may already be gone.
pub struct ApplicationEventSelector<'a> {
    lifecycles: &'a [Lifecycle],
    identifier: Option<ApplicationIdentifier>,
}

impl<'a> ApplicationEventSelector<'a> {
    pub fn new(
        lifecycles: &'a [Lifecycle],
        identifier: Option<&ApplicationIdentifier>,
    ) -> Result<Self, ValidationError> {
        Ok(Self {
            lifecycles,
            identifier: identifier
                .map(ApplicationIdentifier::normalized)
                .transpose()?,
        })
    }

    pub fn matches(
        &self,
        lifecycle: Lifecycle,
        identifier: Option<&ApplicationIdentifier>,
    ) -> bool {
        self.lifecycles.contains(&lifecycle)
            && self
                .identifier
                .as_ref()
                .is_none_or(|expected| Some(expected) == identifier)
    }
}

/// A polling adapter supplies complete snapshots; the core derives transitions.
/// This deliberately contains no regular-app, exclusion or product profile policy.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ApplicationState {
    pub applications: Vec<ApplicationSnapshot>,
    pub frontmost: Option<ProcessIdentity>,
}

impl ApplicationState {
    fn indexed(&self) -> Result<BTreeMap<u32, ApplicationSnapshot>, ValidationError> {
        let mut applications = BTreeMap::new();
        for application in &self.applications {
            application.identity.validate()?;
            if application.terminated {
                return Err(ValidationError::Terminated);
            }
            let Entry::Vacant(entry) = applications.entry(application.identity.process_id) else {
                return Err(ValidationError::DuplicateProcess);
            };
            entry.insert(ApplicationSnapshot {
                identity: application.identity,
                identifier: application
                    .identifier
                    .as_ref()
                    .map(ApplicationIdentifier::normalized)
                    .transpose()?,
                display_name: application.display_name.clone(),
                terminated: false,
            });
        }
        if let Some(identity) = self.frontmost {
            identity.validate()?;
            if applications
                .get(&identity.process_id)
                .is_none_or(|app| app.identity != identity)
            {
                return Err(ValidationError::TargetChanged);
            }
        }
        Ok(applications)
    }

    /// Events use process identity rather than PID, so a PID reused between
    /// samples produces termination and launch rather than a silent replacement.
    pub fn reconcile(&self, next: &Self) -> Result<(Self, Vec<ApplicationEvent>), ValidationError> {
        let previous = self.indexed()?;
        let current = next.indexed()?;
        let mut events = Vec::new();
        let focus_changed = self.frontmost != next.frontmost;
        if focus_changed && let Some(identity) = self.frontmost {
            events.push(ApplicationEvent {
                lifecycle: Lifecycle::Deactivated,
                application: previous[&identity.process_id].clone(),
            });
        }
        for (process_id, application) in &previous {
            if current
                .get(process_id)
                .is_none_or(|next| next.identity != application.identity)
            {
                let mut application = application.clone();
                application.terminated = true;
                events.push(ApplicationEvent {
                    lifecycle: Lifecycle::Terminated,
                    application,
                });
            }
        }
        for (process_id, application) in &current {
            if previous
                .get(process_id)
                .is_none_or(|before| before.identity != application.identity)
            {
                events.push(ApplicationEvent {
                    lifecycle: Lifecycle::Launched,
                    application: application.clone(),
                });
            }
        }
        if focus_changed && let Some(identity) = next.frontmost {
            events.push(ApplicationEvent {
                lifecycle: Lifecycle::Activated,
                application: current[&identity.process_id].clone(),
            });
        }
        Ok((
            Self {
                applications: current.into_values().collect(),
                frontmost: next.frontmost,
            },
            events,
        ))
    }
}
