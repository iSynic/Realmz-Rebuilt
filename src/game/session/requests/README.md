# Interaction request bodies

Start with `InteractionRequest` to understand the stable kind registry and wire envelope. The files here own the typed payload carried by each request kind. A payload contains only detached transaction data, serializes through `to_data()`, and never reaches into live session state.

When adding or changing a request, update its body here, the matching decoder path in `interaction_request.gd` or `interaction_request_service_decoder.gd`, its response type, and the owning gameplay and presentation tests together. Keep serialized kind names, field names, versions, and optional-field behavior stable unless an explicit save migration owns the change.

Dialog bodies cover acknowledgement, age-update, and binary-choice boundaries. Selection and encounter bodies cover indexed choices, character or ally selection, Complex Encounters, thief actions, and the Pick Lock tumbler sequence. Service bodies cover Shop, Temple, and Bank; reward bodies cover Treasure and Level Up; combat and lifecycle each own their detached command boundary. The central request class remains the small registry and codec entry point; it must not regain feature payload implementations.
