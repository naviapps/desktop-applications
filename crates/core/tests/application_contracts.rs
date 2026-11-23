use desktop_applications::{
    ApplicationEvent, ApplicationEventSelector, ApplicationIdentifier, ApplicationSnapshot,
    ApplicationState, IdentifierKind, Lifecycle, ProcessIdentity, ValidationError, validate_target,
};
use serde_json::json;

fn snapshot(pid: u32, start_time: u64) -> ApplicationSnapshot {
    ApplicationSnapshot {
        identity: ProcessIdentity {
            process_id: pid,
            start_time,
        },
        identifier: Some(ApplicationIdentifier {
            kind: IdentifierKind::Bundle,
            value: "com.example.app".into(),
        }),
        display_name: None,
        terminated: false,
    }
}

#[test]
fn event_selection_matches_the_requested_lifecycle_and_exact_identifier_namespace() {
    let lifecycles = [
        Lifecycle::Launched,
        Lifecycle::Terminated,
        Lifecycle::Activated,
        Lifecycle::Deactivated,
    ];
    for (kind, other_kind, requested, exact, decomposed) in [
        (
            IdentifierKind::Bundle,
            IdentifierKind::Executable,
            " Café.Fixture\n",
            "Café.Fixture",
            "Cafe\u{301}.Fixture",
        ),
        (
            IdentifierKind::Executable,
            IdentifierKind::Bundle,
            r"C:\Owned\Café.exe",
            r"C:\Owned\Café.exe",
            "C:\\Owned\\Cafe\u{301}.exe",
        ),
        (
            IdentifierKind::AppUserModel,
            IdentifierKind::Bundle,
            "Café!App",
            "Café!App",
            "Cafe\u{301}!App",
        ),
    ] {
        let identifier = |kind, value: &str| ApplicationIdentifier {
            kind,
            value: value.into(),
        };
        let requested = identifier(kind, requested);
        let recorded = identifier(kind, exact);
        let mismatches = [
            identifier(other_kind, exact),
            identifier(kind, &exact.to_lowercase()),
            identifier(kind, decomposed),
            identifier(kind, &format!(" {exact}\n")),
        ];
        let empty = ApplicationEventSelector::new(&[], Some(&requested)).unwrap();
        for selected in lifecycles {
            assert!(!empty.matches(selected, Some(&recorded)));
            let filter = [selected];
            let selector = ApplicationEventSelector::new(&filter, Some(&requested)).unwrap();
            for observed in lifecycles {
                assert_eq!(
                    selector.matches(observed, Some(&recorded)),
                    observed == selected,
                    "{kind:?} {selected:?} must match only the selected lifecycle"
                );
                assert!(!selector.matches(observed, None), "{kind:?} {observed:?}");
                for candidate in &mismatches {
                    assert!(
                        !selector.matches(observed, Some(candidate)),
                        "{kind:?} {selected:?} matched {observed:?} for {candidate:?}"
                    );
                }
            }
        }
    }
    let filter = [Lifecycle::Terminated, Lifecycle::Activated];
    let unrestricted = ApplicationEventSelector::new(&filter, None).unwrap();
    let empty = ApplicationEventSelector::new(&[], None).unwrap();
    let blank = ApplicationIdentifier {
        kind: IdentifierKind::Bundle,
        value: " ".into(),
    };
    for lifecycle in lifecycles {
        assert_eq!(
            unrestricted.matches(lifecycle, None),
            filter.contains(&lifecycle)
        );
        assert_eq!(
            unrestricted.matches(lifecycle, Some(&blank)),
            filter.contains(&lifecycle)
        );
        assert!(!empty.matches(lifecycle, None));
        assert!(!empty.matches(lifecycle, Some(&blank)));
    }
    assert!(matches!(
        ApplicationEventSelector::new(&[Lifecycle::Terminated], Some(&blank)),
        Err(ValidationError::InvalidIdentifier)
    ));
}

#[test]
fn bundle_lookup_trims_surrounding_whitespace_and_rejects_blank_or_control_input() {
    for (value, expected) in [
        (" com.Example.App\n", Ok("com.Example.App")),
        ("\u{2003}com.Example.App\u{a0}", Ok("com.Example.App")),
        ("\u{200b}com.Example.App", Ok("\u{200b}com.Example.App")),
        ("com.example app", Ok("com.example app")),
        ("", Err(ValidationError::InvalidIdentifier)),
        (" \t\n", Err(ValidationError::InvalidIdentifier)),
        ("com.\nexample", Err(ValidationError::InvalidIdentifier)),
        ("a\0b", Err(ValidationError::InvalidIdentifier)),
    ] {
        let result = ApplicationIdentifier {
            kind: IdentifierKind::Bundle,
            value: value.into(),
        }
        .normalized();
        assert_eq!(
            result.as_ref().map(|id| id.value.as_str()).map_err(|e| *e),
            expected
        );
    }
}

#[test]
fn opaque_lookup_keys_preserve_exact_spelling() {
    for kind in [IdentifierKind::Executable, IdentifierKind::AppUserModel] {
        for value in ["\u{200b} app \u{200b}", "é.app", "e\u{301}.app"] {
            let identifier = ApplicationIdentifier {
                kind,
                value: value.into(),
            };
            assert_eq!(identifier.normalized(), Ok(identifier));
        }
        assert_eq!(
            (ApplicationIdentifier {
                kind,
                value: "a\0b".into(),
            })
            .normalized(),
            Err(ValidationError::InvalidIdentifier)
        );
    }
}

#[test]
fn recorded_control_rechecks_live_process_and_optional_identifier() {
    let recorded = snapshot(40, 100);
    let validated = ApplicationSnapshot {
        display_name: Some("Fresh native display name".into()),
        ..recorded.clone()
    };
    assert_eq!(validate_target(&recorded, &validated), Ok(()));

    let unavailable = ApplicationSnapshot {
        identifier: None,
        ..recorded.clone()
    };
    let invalid_targets = [
        (snapshot(0, 100), ValidationError::InvalidProcessId),
        (snapshot(40, 0), ValidationError::IdentityUnavailable),
        (snapshot(40, 101), ValidationError::TargetChanged),
        (unavailable.clone(), ValidationError::IdentifierUnavailable),
        (
            ApplicationSnapshot {
                identifier: Some(ApplicationIdentifier {
                    kind: IdentifierKind::Executable,
                    value: "com.example.app".into(),
                }),
                ..recorded.clone()
            },
            ValidationError::IdentifierMismatch,
        ),
        (
            ApplicationSnapshot {
                terminated: true,
                ..recorded.clone()
            },
            ValidationError::Terminated,
        ),
    ];
    for (actual, error) in invalid_targets {
        assert_eq!(
            validate_target(&recorded, &actual),
            Err(error),
            "{actual:?}"
        );
    }
    assert_eq!(
        validate_target(&snapshot(40, 0), &recorded),
        Err(ValidationError::IdentityUnavailable)
    );
    assert_eq!(validate_target(&unavailable, &recorded), Ok(()));
}

#[test]
fn reconciliation_orders_mixed_transitions_and_retains_the_matching_sample() {
    let first_terminated = snapshot(10, 100);
    let old_foreground = snapshot(40, 100);
    let last_terminated = snapshot(60, 100);
    let first_launched = snapshot(15, 100);
    let second_launched = snapshot(30, 100);
    let new_foreground = snapshot(55, 100);
    let retained = snapshot(20, 100);
    let refreshed = ApplicationSnapshot {
        display_name: Some("New display name".into()),
        ..retained.clone()
    };
    let previous = ApplicationState {
        applications: vec![
            last_terminated.clone(),
            old_foreground.clone(),
            first_terminated.clone(),
            retained,
        ],
        frontmost: Some(old_foreground.identity),
    };
    let current = ApplicationState {
        applications: vec![
            new_foreground.clone(),
            refreshed.clone(),
            second_launched.clone(),
            first_launched.clone(),
        ],
        frontmost: Some(new_foreground.identity),
    };

    let (state, events) = previous.reconcile(&current).unwrap();
    assert_eq!(
        state.applications,
        [
            first_launched.clone(),
            refreshed,
            second_launched.clone(),
            new_foreground.clone()
        ]
    );
    assert_eq!(state.frontmost, current.frontmost);
    let expected = [
        (Lifecycle::Deactivated, &old_foreground, false),
        (Lifecycle::Terminated, &first_terminated, true),
        (Lifecycle::Terminated, &old_foreground, true),
        (Lifecycle::Terminated, &last_terminated, true),
        (Lifecycle::Launched, &first_launched, false),
        (Lifecycle::Launched, &second_launched, false),
        (Lifecycle::Launched, &new_foreground, false),
        (Lifecycle::Activated, &new_foreground, false),
    ];
    assert_eq!(events.len(), expected.len());
    for (event, (lifecycle, application, terminated)) in events.iter().zip(expected) {
        assert_eq!(event.lifecycle, lifecycle);
        assert_eq!(
            event.application,
            ApplicationSnapshot {
                terminated,
                ..application.clone()
            }
        );
    }
    assert_eq!(state.reconcile(&current).unwrap(), (state, Vec::new()));
}

#[test]
fn reconciliation_reports_focus_changes_without_replaying_retained_processes() {
    let first = snapshot(10, 100);
    let second = snapshot(20, 100);
    let deactivated_first = ApplicationEvent {
        lifecycle: Lifecycle::Deactivated,
        application: first.clone(),
    };
    let activated_second = ApplicationEvent {
        lifecycle: Lifecycle::Activated,
        application: second.clone(),
    };
    for (previous, current, expected) in [
        (None, None, vec![]),
        (Some(first.identity), Some(first.identity), vec![]),
        (None, Some(second.identity), vec![activated_second.clone()]),
        (Some(first.identity), None, vec![deactivated_first.clone()]),
        (
            Some(first.identity),
            Some(second.identity),
            vec![deactivated_first, activated_second],
        ),
    ] {
        let previous = ApplicationState {
            applications: vec![second.clone(), first.clone()],
            frontmost: previous,
        };
        let current = ApplicationState {
            applications: vec![first.clone(), second.clone()],
            frontmost: current,
        };
        assert_eq!(previous.reconcile(&current).unwrap(), (current, expected));
    }
}

#[test]
fn snapshot_equality_and_reconciliation_preserve_display_name_spelling() {
    let composed = ApplicationSnapshot {
        display_name: Some("Caf\u{e9}".into()),
        ..snapshot(40, 100)
    };
    let decomposed = ApplicationSnapshot {
        display_name: Some("Cafe\u{301}".into()),
        ..composed.clone()
    };
    assert_ne!(composed, decomposed);
    assert_ne!(
        ApplicationEvent {
            lifecycle: Lifecycle::Activated,
            application: composed.clone(),
        },
        ApplicationEvent {
            lifecycle: Lifecycle::Activated,
            application: decomposed.clone(),
        },
    );
    let absent = ApplicationSnapshot {
        display_name: None,
        ..composed.clone()
    };
    let sample = |application: &ApplicationSnapshot| ApplicationState {
        applications: vec![application.clone()],
        frontmost: Some(application.identity),
    };
    for (before, after, wire_name) in [
        (&composed, &decomposed, json!("Cafe\u{301}")),
        (&decomposed, &composed, json!("Caf\u{e9}")),
        (&composed, &absent, json!(null)),
        (&absent, &decomposed, json!("Cafe\u{301}")),
    ] {
        let previous = sample(before);
        let current = sample(after);
        let (state, events) = previous.reconcile(&current).unwrap();
        assert_ne!(previous, state);
        assert_eq!(current, state);
        assert!(events.is_empty());
        assert_eq!(
            serde_json::to_value(state).unwrap()["applications"][0]["displayName"],
            wire_name
        );
    }
}

#[test]
fn reconciliation_normalizes_and_orders_a_complete_sample() {
    let first = snapshot(10, 100);
    let mut last = snapshot(20, 100);
    last.identifier.as_mut().unwrap().value = " com.example.other \n".into();
    let (state, events) = ApplicationState::default()
        .reconcile(&ApplicationState {
            applications: vec![last.clone(), first.clone()],
            frontmost: None,
        })
        .unwrap();
    last.identifier.as_mut().unwrap().value = "com.example.other".into();
    assert_eq!(
        state,
        ApplicationState {
            applications: vec![first, last],
            frontmost: None,
        }
    );
    assert!(
        events
            .iter()
            .all(|event| event.lifecycle == Lifecycle::Launched)
    );
    assert_eq!(
        events
            .into_iter()
            .map(|event| event.application)
            .collect::<Vec<_>>(),
        state.applications
    );
}

#[test]
fn reconciliation_rejects_invalid_previous_and_current_samples() {
    let original = snapshot(40, 100);
    let replacement = snapshot(40, 101);
    let mut invalid_identifier = snapshot(40, 100);
    invalid_identifier.identifier.as_mut().unwrap().value = " \t".into();
    let empty = ApplicationState::default();
    for (applications, frontmost, expected) in [
        (
            vec![original.clone(), replacement.clone()],
            None,
            ValidationError::DuplicateProcess,
        ),
        (
            vec![original.clone(), original.clone()],
            Some(original.identity),
            ValidationError::DuplicateProcess,
        ),
        (
            vec![replacement],
            Some(original.identity),
            ValidationError::TargetChanged,
        ),
        (
            vec![original.clone()],
            Some(snapshot(0, 100).identity),
            ValidationError::InvalidProcessId,
        ),
        (
            vec![original.clone()],
            Some(snapshot(40, 0).identity),
            ValidationError::IdentityUnavailable,
        ),
        (
            vec![snapshot(40, 0)],
            None,
            ValidationError::IdentityUnavailable,
        ),
        (
            vec![snapshot(0, 100)],
            None,
            ValidationError::InvalidProcessId,
        ),
        (
            vec![invalid_identifier],
            None,
            ValidationError::InvalidIdentifier,
        ),
        (
            vec![ApplicationSnapshot {
                terminated: true,
                ..original
            }],
            None,
            ValidationError::Terminated,
        ),
    ] {
        let sample = ApplicationState {
            applications,
            frontmost,
        };
        assert_eq!(empty.reconcile(&sample), Err(expected), "{sample:?}");
        assert_eq!(sample.reconcile(&empty), Err(expected), "{sample:?}");
    }
}
