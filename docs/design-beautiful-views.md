# Richer, more beautiful workshop views (2026-11-16)

Toni, 2026-11-16: "the name is Beautiful BOM, so we need to work towards making it beautiful" and
make the non-source part richer. He approved the map teaser ("Yes this sounds good. Let's do it")
and asked to plan the look across all views next.

## Intent

In the workshop the room should see the product's make-up as one picture and remember it; the
views should feel designed, not like a formatted report. Persona and first result as in
`design-workshop-views.md`: a mixed room in front of a projector; first result, "1 chosen,
61 pulled in" understood at a glance.

## Part 1: the map of the product (approved, building)

A sunburst at the top of Composition, titled "How it hangs together", above the existing bars.

- The product is the dark disc in the middle; ring 1 holds its direct dependencies; each further
  ring is one step further away. Every part sits under the parent that reaches it first
  (shortest path, as "Why is it here?" already shows).
- A slice's width is the number of parts it stands for: itself and everything it pulls in.
- Colour is the vendor: the five largest vendors (the same five as "Who wrote it") get one colour
  each; all others are grey. Further rings are lighter tints of the same colour.
- Slices narrower than about 1.4° are merged per parent into one grey "N more" slice, so a 50 MB
  SBOM still draws; at most 12 rings.
- Hover: everything except the path from the product fades; a card at the right names the part,
  its type, ecosystem and depth, the path, licence and hash state. Click opens the component page
  (a merged slice opens Components filtered to that depth).
- The legend (vendors, clickable like the bar) and three reading lines stand at the right.
- Shown only when the SBOM has dependency data from the product; otherwise the existing "How deep
  it goes" messages explain why.
- Anti-goals unchanged: no invented scores, nothing the SBOM does not say. Unreachable parts are
  not on the map; the caption counts them, as today.

Layout code (rings, angles, merging) lives in BOMCore (`DependencyMap`) and is unit-tested; the
app only draws it.

## Part 2: one look across all views (to be mocked up, then approved)

- A calm categorical palette, one meaning per colour family: vendors, ecosystems, licence
  families; system blue stays for links and selection only.
- Bars, rings and bars of the histogram grow in gently when a view opens (respecting Reduce
  Motion).
- Chips for ecosystem and licence in the Components table.
- Headings pick up the serif of the wordmark.
- Completeness as coverage: each TR field gets "n of N components" as a bar (counts, never a
  score), with one summary row.

Mockups first, in the gallery; this part is built after Toni approves them.
