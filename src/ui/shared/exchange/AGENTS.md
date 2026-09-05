# Shared exchange component contract

## Purpose

Own reusable presentation-only item ledgers and drag/drop records shared by Inventory Trade and Shop.

## Ownership

- `classic_exchange_item_button.tscn` owns one exact item record and its scene-authored drag preview.
- `ClassicExchangeLedger` binds exported item rows and translates drops into stable source and destination identities.

## Local Contracts

- Callers recheck the supplied exact instance, destination, and availability before emitting an existing typed mutation.
- Drag and drop is never a second gameplay path; visible click and keyboard actions remain available.
- Exchange components do not calculate capacity, price, eligibility, or item knowledge.

## Work Guidance

- Keep reusable drag payload mechanics here and feature-specific transaction commands with Inventory or Services.

## Verification

- Run Inventory, Shop, Classic UI system, and Realmz Builder preview fixtures after exchange changes.

## Child DOX Index
