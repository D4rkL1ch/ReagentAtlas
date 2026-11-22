# Reagent Atlas

## 1.2.1

- **Fixed:** owned counts could be far too high, for example in Waylaid Crate tooltips and the tracker. When the game didn't report your realm name, a character got saved twice and its old bag and bank counts were added on top of the current ones. The two entries are now merged automatically when you log in on that character, and it shows only once in the character list.
- **Changed:** item tooltips (also when hovering items in the reagent browser) and Waylaid Crate tooltips now show where your items are, by name: your bags and bank, each character that has some, and the warband bank. For example "Owned: 66 (3 bags, 27 bank, Brissa 4, warband 32)" or "have 27 in bank".
