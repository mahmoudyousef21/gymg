# Design System Specification: Kinetic Cybernetics

## 1. Overview & Creative North Star
**Creative North Star: "The Neon Athlete"**
This design system moves away from the static, data-heavy "spreadsheet" feel of traditional fitness apps. Instead, it treats the interface as a futuristic cockpit. The "Neon Athlete" aesthetic leverages high-contrast editorial typography, deep tonal layering, and "active-glow" states to make the act of logging a workout feel like upgrading a machine.

To break the "template" look, we utilize **Asymmetric Kinetic Energy**. This means intentional offsets in layout, overlapping glass cards that break the container edge, and a typography scale that favors dramatic size shifts to create a clear, authoritative information hierarchy.

---

## 2. Colors & Surface Philosophy

### The "No-Line" Rule
Traditional borders are prohibited. Sectioning is achieved through **Tonal Transitions**. Use `surface_container_low` against a `surface` background to define areas. Boundaries should be felt, not seen.

### Surface Hierarchy & Nesting
Depth is built through a "Stacking" logic. The deeper the content is nested, the higher the surface container tier:
1.  **Base Layer:** `surface` (#0e0e0e) – The foundation.
2.  **Section Layer:** `surface_container_low` (#131313) – Large content blocks.
3.  **Interaction Layer:** `surface_container_highest` (#262626) – Interactive cards or modals.

### The Glass & Gradient Rule
To achieve the "Futuristic" personality, use **Glassmorphism** for floating UI elements (e.g., bottom navigation or active stopwatches). 
*   **Formula:** `surface_variant` at 60% opacity + `backdrop-filter: blur(12px)`.
*   **Signature Textures:** Main Action Buttons should not be flat. Use a linear gradient: `primary` (#81ecff) to `primary_container` (#00e3fd) at a 135° angle to simulate a glowing light source.

---

## 3. Typography: The Performance Scale

We utilize two typefaces to balance "High-Performance" utility with "Futuristic" energy.

*   **Display & Headlines:** *Space Grotesk*. A technical, wide-set sans-serif that feels like engineering. Used for PRs (Personal Records), tier names, and large stats.
*   **UI & Body:** *Inter*. A hyper-legible workhorse for functional data, descriptions, and labels.

| Role | Token | Font | Size | Case | Personality |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hero Stats** | `display-lg` | Space Grotesk | 3.5rem | Bold | Authoritative |
| **Section Title** | `headline-sm` | Space Grotesk | 1.5rem | Medium | Structural |
| **Card Header** | `title-md` | Inter | 1.125rem | Semi-Bold | Functional |
| **Data Label** | `label-md` | Inter | 0.75rem | All Caps (Track: 5%) | Technical |

---

## 4. Elevation & Depth

### The Layering Principle
Do not use shadows to lift items off the background. Instead, use "Tonal Lift." A card is "raised" by being one step lighter in the `surface_container` scale than the layer beneath it.

### The "Ghost Border" Fallback
If a visual separator is required for accessibility, use a **Ghost Border**:
*   **Token:** `outline_variant` (#494847)
*   **Opacity:** 15%
*   **Width:** 1px

### Active States & The "Neon Glow"
When a component is "Active" (e.g., a selected muscle group or an active timer), apply a neon outer glow:
*   **Glow:** `box-shadow: 0 0 15px 2px rgba(0, 229, 255, 0.3);` using the `primary` token.

---

## 5. Components

### Primary Action Button (The "Lift" Button)
*   **Background:** Gradient (`primary` to `primary_container`).
*   **Corner Radius:** `md` (0.375rem).
*   **Text:** `title-sm` / `on_primary` (Bold).
*   **Effect:** On hover/active, increase glow spread by 4px.

### Tier Badges (3D Glass)
*   **Visuals:** Use `surface_bright` with a 20% opacity. 
*   **3D Effect:** A 1px inner-top-border using `on_surface` at 30% opacity to simulate a "highlight" on the top edge of the glass.
*   **Tier Tints:** 
    *   *Iron:* `outline` tint.
    *   *Elite:* `secondary` (#ff734a) neon glow.

### Workout Cards
*   **Layout:** No dividers. Use `body-sm` for secondary metadata with `on_surface_variant` (#adaaaa).
*   **Spacing:** Use `1.5rem` (xl) vertical padding to separate sets/reps.
*   **Separation:** Background color shift from `surface` to `surface_container_lowest`.

### Input Fields (Technical Entry)
*   **Background:** `surface_container_highest`.
*   **Border:** None (Ghost Border 10% on focus).
*   **Focus State:** The label transitions to `primary` (#81ecff) color.

---

## 6. Do's and Don'ts

### Do
*   **Do** use extreme scale. Make your "Weight Lifted" numbers massive (`display-lg`) and your unit labels small (`label-sm`).
*   **Do** overlap elements. Let a 3D badge sit 50% outside the top-right corner of a card to create depth.
*   **Do** use `secondary` (#ff734a) exclusively for "High-Energy" moments: Breaking a PR, finishing a workout, or a "Tier Up" notification.

### Don't
*   **Don't** use pure white (#FFFFFF) for body text. Use `on_surface_variant` (#adaaaa) to reduce eye strain in dark mode.
*   **Don't** use standard 1px lines to separate list items. Use 16px of vertical whitespace.
*   **Don't** use standard "Drop Shadows." If an element needs to float, use Backdrop Blur and Tonal Layering.