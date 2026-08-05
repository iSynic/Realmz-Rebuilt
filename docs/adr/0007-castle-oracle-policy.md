# ADR 0007: Use pinned Castle as the behavioral oracle

Status: accepted

Castle commit `491816ad60037394f92c428e99c004494d3c28b3` supplies source/control-flow and observable runtime evidence. Differential fixtures use synthetic data, controlled input, and injected RNG. Evidence labels distinguish source observation, Castle runtime, runtime tests, and live route proof. Dirty source checkouts and commercial scenario payloads are never copied.
