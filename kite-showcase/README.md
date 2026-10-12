# Kite Showcase (experimental)

The question: once a merchant creates any discount in Kite (including a free-form custom one), how does it show up on the storefront, and how do we help them choose?

The idea this page explores: Kite reads every discount as three things, whatever template built it:

- **What the shopper does**: the steps they can act on (spend, buy a number of items, add a product, enter a code).
- **What they get**: the reward, and whether it changes each item's price or the order total.
- **Who can get it**: hidden rules the shopper can't act on (customer tags, markets). These are never shown as steps.

From that shape, each display format either fits, fits with a catch, or doesn't fit, and Kite says why. For example, a progress bar needs one measure that grows toward a goal. "Add a serum, spend $60, be a VIP" has two separate steps and a hidden rule, so it becomes a checklist.

The page also covers the three ways a discount can reach the store: Kite places it, the merchant adds a Kite block anywhere in the theme, or the merchant uses their own design and Kite supplies the live values.

Published page: https://claude.ai/artifact/HJMfwm93FsAx4KTFx8keZ9

`kite-showcase.html` is self-contained; open it in a browser. Products, discounts and prices are examples.
