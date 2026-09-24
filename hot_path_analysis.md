# Revive Adserver: Delivery Hot Path & Waterfall Logic

This document provides a technical overview of the ad delivery hot path in the Revive Adserver repository, focusing on the system's "waterfall logic." It is tailored for readers with a background in C++ and a conceptual understanding of financial or business waterfall distribution models.

## 1. The Ad Delivery Hot Path

The "hot path" is the critical, latency-sensitive sequence of code executed every time an ad impression is requested. In Revive, this process is optimized heavily around caching and early exits.

### Execution Flow:
1. **Entry Point (`www/delivery/*.php`)**: Ad requests from client browsers arrive via specific delivery scripts (e.g., `ajs.php` for JavaScript, `afr.php` for iframes, `spc.php` for Single Page Call).
2. **Selection Orchestration (`lib/max/Delivery/adSelect.php :: MAX_adSelect()`)**: The entry scripts marshal request data (zone IDs, source, targeting context) and invoke the core selection engine.
3. **Zone Resolution (`_adSelectZone()`)**: If an ad is requested for a specific Zone (an ad placement on a website), it fetches the zone configuration and all linked, active campaigns from memory cache (`MAX_cacheGetZoneLinkedAdInfos`).
4. **The Waterfall (`_adSelectInnerLoop()`)**: Ads are funneled through priority-based tiers (the waterfall).
5. **Constraint Filtering (`_adSelectCheckCriteria()`)**: Before an ad is selected from a tier, it undergoes rigorous validation (frequency capping, expiration, targeting ACLs). Non-matching ads are discarded.
6. **Selection (`_adSelect()`)**: A stochastic (randomized) selection is made among the remaining eligible ads in the highest successful tier based on configured weights/priorities.
7. **Rendering (`lib/max/Delivery/adRender.php :: MAX_adRender()`)**: The winning ad's metadata is translated into the HTML/JS payload and returned to the client.

---

## 2. The Waterfall Logic

Revive's ad selection relies on a strict priority cascade—conceptually similar to a cash flow waterfall in structured finance, where senior tranches are paid out before subordinate tranches.

The waterfall is defined in `adSelect.php` as a static array of campaign types:

```php
$aCampaignTypes = [
    'xAds' => false,                             // Exclusive (Overrides)
    'ads'  => [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],   // Contract / High Priority
    'lAds' => false,                             // Remnant / Low Priority
    'eAds' => [-2],                              // eCPM Optimization
];
```

The system iterates through these tranches sequentially. Once an ad is successfully picked from a higher tranche, the system exits the loop (short-circuits) and does not evaluate lower tranches.

### Tranche Breakdown:

1. **`xAds` (Exclusive / Override Campaigns):**
   - **Analogue:** Super-senior debt.
   - **Function:** Bypasses all normal weighting. If an exclusive campaign is active and matches the targeting criteria for a zone, it takes 100% of the traffic.

2. **`ads` (Contract / High Priority Campaigns):**
   - **Analogue:** Senior tranches (Class A, B, C...).
   - **Function:** This tier is subdivided into 10 priority levels (10 being the highest). It is used to fulfill guaranteed inventory contracts. The algorithm calculates the probability needed to hit delivery targets over time and scales priorities accordingly.

3. **`lAds` (Remnant / Low Priority Campaigns):**
   - **Analogue:** Subordinated/Mezzanine debt.
   - **Function:** These campaigns have no guaranteed delivery targets and run indefinitely or until a click/impression limit is hit. They are weighted relative to one another to absorb whatever inventory remains after the `ads` tranche is satisfied.

4. **`eAds` (eCPM Optimization Campaigns):**
   - **Analogue:** Equity tranche / Yield optimization.
   - **Function:** When all fixed-priority inventory is exhausted, this tier attempts to maximize revenue by evaluating network campaigns. It prioritizes ads based on Effective Cost Per Mille (eCPM)—meaning the ad that yields the highest expected revenue per 1000 impressions wins.

### Selection Mechanics (C++ perspective)

Under the hood, if multiple ads exist within the same active tranche (e.g., two Remnant ads), the selection is not deterministic but weighted. 
1. The engine calculates an aggregate `total_priority` (sum of all ad weights in the pool).
2. It generates a pseudo-random float between `0.0` and `1.0`.
3. It iterates through the ad pool, maintaining a cumulative sum (`high` bound), and selects the ad whose probability slice captures the random number.
