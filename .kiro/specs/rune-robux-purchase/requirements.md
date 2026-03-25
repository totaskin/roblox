# Requirements Document

## Introduction

The Rune Robux Purchase feature enables players to purchase runes directly with Robux, providing an alternative acquisition path alongside the existing boss-drop system. Players can buy individual runes or rune bundles through Roblox's Developer Products system. Purchased runes are immediately added to the player's persistent Rune_Inventory and saved via DataManager.

This feature integrates with the existing RuneManager, EconomyManager, and DataManager modules, following the established patterns from GamepassManager for Roblox monetization.

## Glossary

- **Rune_Inventory**: The per-player collection of runes, tracked as a count per rune type (ids 1–10). Persists across sessions via DataManager.
- **Rune_Type**: One of the 10 elemental rune types (Ember, Frost, Spark, Spore, Shadow, Radiance, Stone, Gale, Arcane, Void).
- **Developer_Product**: A Roblox monetization item that can be purchased multiple times with Robux. Used for consumable purchases like runes.
- **Rune_Product**: A Developer_Product configured to grant one or more runes of a specific Rune_Type when purchased.
- **Rune_Bundle_Product**: A Developer_Product configured to grant multiple runes of various types in a single purchase.
- **Purchase_Handler**: The server-side module responsible for processing Roblox MarketplaceService purchase receipts and granting runes.
- **Rune_Shop_UI**: The client-side UI that displays available rune products and allows players to initiate purchases.
- **Receipt_Processing**: The Roblox callback mechanism for handling Developer_Product purchases via ProcessReceipt.
- **Purchase_Receipt**: The data structure provided by Roblox containing purchase details (PlayerId, ProductId, PurchaseId).

## Requirements

### Requirement 1: Developer Product Configuration

**User Story:** As a developer, I want to define rune products with their Robux prices and rune rewards, so that the purchase system knows what to grant for each product.

#### Acceptance Criteria

1. THE Purchase_Handler SHALL define a Rune_Product_Table mapping each Developer_Product id to its reward configuration (Rune_Type id and quantity).
2. THE Rune_Product_Table SHALL include single-rune products for each of the 10 Rune_Types, each granting 1 rune of that type.
3. THE Rune_Product_Table SHALL include at least one Rune_Bundle_Product that grants multiple runes of random types.
4. WHEN a Developer_Product id is not found in the Rune_Product_Table, THE Purchase_Handler SHALL reject the purchase and log a warning.

### Requirement 2: Purchase Receipt Processing

**User Story:** As a player, I want my rune purchases to be processed reliably, so that I receive my runes after paying Robux.

#### Acceptance Criteria

1. THE Purchase_Handler SHALL register a ProcessReceipt callback with MarketplaceService to handle all Developer_Product purchases.
2. WHEN a Purchase_Receipt is received, THE Purchase_Handler SHALL validate that the ProductId exists in the Rune_Product_Table.
3. WHEN a valid rune purchase is processed, THE Purchase_Handler SHALL increment the player's Rune_Inventory by the configured quantity for each Rune_Type in the product reward.
4. WHEN a rune purchase is successfully granted, THE Purchase_Handler SHALL return Enum.ProductPurchaseDecision.PurchaseGranted to acknowledge the receipt.
5. IF the player is not in the game when the receipt is processed, THEN THE Purchase_Handler SHALL return Enum.ProductPurchaseDecision.NotProcessedYet to allow retry on next join.
6. WHEN a purchase is granted, THE Purchase_Handler SHALL call DataManager.markDirty to ensure the runes are persisted.

### Requirement 3: Rune Delivery to Player

**User Story:** As a player, I want purchased runes to appear in my inventory immediately, so that I can use them right away.

#### Acceptance Criteria

1. WHEN a rune purchase is granted, THE Purchase_Handler SHALL add the runes to the player's Rune_Inventory via RuneManager.
2. WHEN runes are added to the inventory, THE Purchase_Handler SHALL fire a RuneInventoryUpdate remote event to notify the purchasing player's client.
3. THE Purchase_Handler SHALL grant runes atomically—either all runes in a product are granted or none are.
4. WHEN a Rune_Bundle_Product is purchased, THE Purchase_Handler SHALL use the existing ResourceData.rollResourceDrop function to determine random rune types.

### Requirement 4: Rune Shop UI Display

**User Story:** As a player, I want to see a shop interface showing available rune products, so that I can browse and purchase runes.

#### Acceptance Criteria

1. THE Rune_Shop_UI SHALL display a list of all available Rune_Products with their names, Robux prices, and rune rewards.
2. THE Rune_Shop_UI SHALL display each Rune_Type product with the corresponding rune color and icon from ResourceData.
3. THE Rune_Shop_UI SHALL display Rune_Bundle_Products with a clear indication of the bundle contents (e.g., "5 Random Runes").
4. THE Rune_Shop_UI SHALL be accessible from the lobby via a "Rune Shop" button.
5. WHILE the player is in an active game session, THE Rune_Shop_UI SHALL remain accessible via a shop button in the RuneHUD.

### Requirement 5: Purchase Flow Initiation

**User Story:** As a player, I want to click a buy button to purchase runes, so that the purchase process is straightforward.

#### Acceptance Criteria

1. WHEN a player clicks a Rune_Product in the Rune_Shop_UI, THE Rune_Shop_UI SHALL call MarketplaceService:PromptProductPurchase with the corresponding Developer_Product id.
2. THE Rune_Shop_UI SHALL display the player's current Rune_Inventory counts alongside each Rune_Product for reference.
3. WHEN a purchase prompt is displayed, THE Rune_Shop_UI SHALL disable the clicked product button until the prompt is closed or completed.
4. IF the player cancels the purchase prompt, THEN THE Rune_Shop_UI SHALL re-enable the product button with no other side effects.

### Requirement 6: Purchase Confirmation Feedback

**User Story:** As a player, I want to see confirmation when my purchase succeeds, so that I know my runes were granted.

#### Acceptance Criteria

1. WHEN a rune purchase is successfully granted, THE Rune_Shop_UI SHALL display a success notification showing the runes received.
2. WHEN a rune purchase is successfully granted, THE Rune_Shop_UI SHALL update the displayed inventory counts to reflect the new totals.
3. IF a purchase fails or is cancelled, THEN THE Rune_Shop_UI SHALL NOT display a success notification.
4. THE success notification SHALL auto-dismiss after 3 seconds or when the player clicks to dismiss it.

### Requirement 7: Purchase Error Handling

**User Story:** As a player, I want to be informed if something goes wrong with my purchase, so that I know to try again or contact support.

#### Acceptance Criteria

1. IF the Purchase_Handler encounters an error while granting runes, THEN THE Purchase_Handler SHALL log the error with the PurchaseId for support investigation.
2. IF the Purchase_Handler cannot grant runes due to an error, THEN THE Purchase_Handler SHALL return Enum.ProductPurchaseDecision.NotProcessedYet to allow Roblox to retry.
3. IF a player attempts to purchase while disconnected from the server, THEN THE Rune_Shop_UI SHALL display an error message "Unable to complete purchase. Please try again."
4. THE Purchase_Handler SHALL NOT grant duplicate runes for the same PurchaseId if the receipt is processed multiple times.

### Requirement 8: Integration with Existing Systems

**User Story:** As a developer, I want the purchase system to integrate cleanly with existing rune and data systems, so that the codebase remains maintainable.

#### Acceptance Criteria

1. THE Purchase_Handler SHALL use RuneManager.setInventory or a new RuneManager.addRunes function to grant purchased runes.
2. THE Purchase_Handler SHALL follow the same module pattern as GamepassManager for MarketplaceService integration.
3. WHEN runes are granted via purchase, THE RuneManager SHALL treat them identically to runes earned from boss kills for all subsequent operations.
4. THE Rune_Shop_UI SHALL reuse the existing rune display components from RuneHUD where applicable.
5. THE Purchase_Handler SHALL be implemented as a new server module (RunePurchaseManager.luau) that coordinates with RuneManager and DataManager.
