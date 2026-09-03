# Setup UI

This folder owns the stable application surfaces shown before ordinary exploration: the installed-scenario browser and the retained party setup workspace. Party assembly and the five-step character creator are modes of the same workspace so switching modes preserves the six party slots and current campaign context.

`CampaignLibraryController` binds campaign summaries and package-operation state to `campaign_selection_panel.tscn`. `CampaignPartySetupController` mounts that panel beside `party_setup_workspace.tscn`, then delegates variable Character File rows, party slots, and character-draft content to the assembly and creation controllers.

The scenes own panels, headings, scroll regions, options, and actions. Controllers may populate changing records and bind signals, but they must not reconstruct those stable controls. Startup changes are performance-sensitive because these resources are prepared in the background application graph; use three warmed `tools/startup_probe.gd` samples and the presentation shell fixtures.
