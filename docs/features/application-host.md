# Application host

`RealmzApplication` is the visible composition root. It constructs dependencies, owns the replaceable session controller, translates host input, coordinates repositories, and sends detached state to presentation. `StartupFrontDoor` owns the first frame and background construction; neither contains game rules.

Follow an input from `ApplicationInputRouter` to a typed session command, and a committed step back through the presentation coordinator. Keep dependency construction explicit and keep campaign loading cancellable. Startup-sensitive changes require three warmed `startup_probe.gd` samples and the ordinary front-door test path.
