# Application host

`RealmzApplication` is the visible composition root. It constructs dependencies, owns the replaceable session controller, translates host input, coordinates repositories, and sends detached state to presentation. `StartupFrontDoor` owns the first frame and background construction; neither contains game rules.

Follow an input from `ApplicationInputRouter` to a typed session command, and a committed step back through the presentation coordinator. Keep dependency construction explicit and keep campaign loading cancellable. Startup-sensitive changes require three warmed `startup_probe.gd` samples and the ordinary front-door test path.

The lightweight entry composition is `src/ui/startup_front_door.tscn`; after its launch card draws, it instantiates the directly editable `src/ui/setup/front_door_menu.tscn`. Keeping the menu scene outside the launch scene prevents its imported media from delaying the first frame. The same menu scene is mounted under the loaded shell when needed. `CampaignLibraryController` binds readiness, video and soundtrack lifecycle, and host signals without constructing controls. `src/ui/setup/campaign_selection_panel.tscn` owns its selected scenario, empty library, package progress, install, and refresh states; only its exported campaign row scene repeats for detached installed packages.
