# Tasks: Rune Robux Purchase

## Task 1: Create RunePurchaseManager server module
- [x] 1.1 Create `src/server/RunePurchaseManager.luau` with Rune_Product_Table defining Developer Product IDs mapped to reward configurations (runeTypeId and quantity for single-rune products, isBundle and quantity for bundle products)
- [x] 1.2 Add placeholder product IDs for all 10 single-rune products (one per rune type 1-10, each granting 1 rune) and at least one bundle product (e.g., 5 random runes)
- [x] 1.3 Add processedPurchases cache (`{ [string]: boolean }`) to track processed PurchaseIds for duplicate prevention
- [x] 1.4 Implement `init()` function that registers ProcessReceipt callback with MarketplaceService

## Task 2: Implement ProcessReceipt callback
- [x] 2.1 Implement receipt validation: check if ProductId exists in Rune_Product_Table, return NotProcessedYet and log warning if not found
- [x] 2.2 Implement player validation: check if player is in game via Players:GetPlayerByUserId, return NotProcessedYet if player not found
- [x] 2.3 Implement duplicate prevention: check processedPurchases cache, return PurchaseGranted without granting if PurchaseId already processed
- [x] 2.4 Implement single-rune product granting: call RuneManager.addRunes with configured runeTypeId and quantity
- [x] 2.5 Implement bundle product granting: loop quantity times, call ResourceData.rollResourceDrop for each rune, accumulate grants, call RuneManager.addRunes for each type
- [x] 2.6 After successful grant: add PurchaseId to processedPurchases, call DataManager.markDirty, fire RuneInventoryUpdate and PurchaseSuccess remotes, return PurchaseGranted
- [x] 2.7 Implement error handling: wrap grant logic in pcall, log errors with PurchaseId, return NotProcessedYet on failure

## Task 3: Extend RuneManager with addRunes function
- [x] 3.1 Add `RuneManager.addRunes(userId: number, runeTypeId: number, quantity: number)` function that increments the player's rune inventory by the specified quantity for the given rune type
- [x] 3.2 Validate runeTypeId is in [1, 10] and quantity > 0, return false if invalid
- [x] 3.3 Ensure addRunes uses the same inventory structure as existing rune operations (boss drops, application, return)

## Task 4: Register new remote events
- [x] 4.1 Add `PurchaseSuccess` RemoteEvent to Remotes folder in GameManager or init.server.luau
- [x] 4.2 Ensure RuneInventoryUpdate remote (already exists) is accessible to RunePurchaseManager

## Task 5: Integrate RunePurchaseManager with server init
- [x] 5.1 Add `RunePurchaseManager = require(script.RunePurchaseManager)` to `src/server/init.server.luau`
- [x] 5.2 Call `RunePurchaseManager.init()` after DataManager and RuneManager initialization

## Task 6: Create RuneShopUI client module
- [x] 6.1 Create `src/client/RuneShopUI.luau` with `init()`, `show()`, `hide()`, `setInventory()` functions
- [x] 6.2 Build shop frame with title, close button, and scrollable product list container
- [x] 6.3 Create product display function that shows rune name, color (from ResourceData), current inventory count, and buy button for each single-rune product
- [x] 6.4 Create bundle product display showing "X Random Runes" with buy button
- [x] 6.5 Implement buy button click handler: call MarketplaceService:PromptProductPurchase, disable button until prompt closes
- [x] 6.6 Wire PromptProductPurchaseFinished to re-enable buttons when purchase prompt closes

## Task 7: Implement RuneShopUI feedback
- [x] 7.1 Wire PurchaseSuccess remote: display success notification showing runes received (e.g., "+1 Ember Rune" or "+5 Random Runes")
- [x] 7.2 Implement notification auto-dismiss after 3 seconds or on click
- [x] 7.3 Wire RuneInventoryUpdate remote: update displayed inventory counts in shop UI
- [x] 7.4 Add error handling for disconnection: display "Unable to complete purchase" message if purchase fails

## Task 8: Integrate RuneShopUI with client
- [x] 8.1 Add `RuneShopUI = require(script.RuneShopUI)` and `RuneShopUI.init()` to `src/client/init.client.luau`
- [x] 8.2 Add "Rune Shop" button to LobbyClient UI that calls RuneShopUI.show()
- [x] 8.3 Add shop button to RuneHUD that calls RuneShopUI.show() (accessible during gameplay)
- [x] 8.4 Pass inventory updates to RuneShopUI when RuneInventoryUpdate is received

## Task 9: Add purchase generators to PropertyGen
- [x] 9.1 Add `PropertyGen.productId()` returning random valid or invalid product ID
- [x] 9.2 Add `PropertyGen.purchaseId()` returning random unique purchase ID string
- [x] 9.3 Add `PropertyGen.purchaseReceipt(playerId, productId)` returning mock receipt structure

## Task 10: Create RunePurchaseTestHarness
- [x] 10.1 Create `src/tests/RunePurchaseTestHarness.luau` with mock RunePurchaseManager (in-memory state, no MarketplaceService deps)
- [x] 10.2 Add mock RuneManager that tracks addRunes calls and inventory state
- [x] 10.3 Add mock DataManager that tracks markDirty calls
- [x] 10.4 Add mock Players service for simulating online/offline players
- [x] 10.5 Add helper functions for setting up test scenarios (player online, product configured, etc.)

## Task 11: Implement RunePurchasePropertyTests
- [x] 11.1 Create `src/tests/RunePurchasePropertyTests.luau` with test runner structure matching RunePropertyTests pattern
- [x] 11.2 Implement Property 1: Product Table Validity — verify all entries have valid runeTypeId in [1,10] or isBundle=true, and quantity > 0 (Feature: rune-robux-purchase, Property 1)
- [x] 11.3 Implement Property 2: Invalid Product Rejection — generate random invalid product IDs, verify processReceipt returns NotProcessedYet and inventory unchanged (Feature: rune-robux-purchase, Property 2)
- [x] 11.4 Implement Property 3: Correct Rune Delivery — generate valid purchases, verify inventory increases by exactly configured quantity (Feature: rune-robux-purchase, Property 3)
- [x] 11.5 Implement Property 4: Successful Purchase Returns PurchaseGranted — verify valid purchases return PurchaseGranted enum (Feature: rune-robux-purchase, Property 4)
- [x] 11.6 Implement Property 5: Offline Player Returns NotProcessedYet — simulate offline player, verify NotProcessedYet returned and no inventory change (Feature: rune-robux-purchase, Property 5)
- [x] 11.7 Implement Property 6: Data Persistence on Grant — verify markDirty called after successful grants (Feature: rune-robux-purchase, Property 6)
- [x] 11.8 Implement Property 7: Client Notification on Grant — verify RuneInventoryUpdate fired after successful grants (Feature: rune-robux-purchase, Property 7)
- [x] 11.9 Implement Property 8: Atomic Rune Granting — for multi-rune products, verify either all runes granted or none (Feature: rune-robux-purchase, Property 8)
- [x] 11.10 Implement Property 9: Bundle Uses Random Drop Function — verify bundle purchases call rollResourceDrop for each rune (Feature: rune-robux-purchase, Property 9)
- [x] 11.11 Implement Property 10: Error Returns NotProcessedYet — simulate grant errors, verify NotProcessedYet returned (Feature: rune-robux-purchase, Property 10)
- [x] 11.12 Implement Property 11: Duplicate Purchase Prevention — process same PurchaseId twice, verify runes granted only once (Feature: rune-robux-purchase, Property 11)
- [x] 11.13 Implement Property 12: Purchased Runes Equivalence — verify purchased runes can be applied to turrets and returned on game over identically to dropped runes (Feature: rune-robux-purchase, Property 12)
