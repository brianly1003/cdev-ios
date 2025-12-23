# Test Case 1:
- Still get "..." when I enter long texts without enter line break 
=> I see the issue. The lineLimit: 1...5 is preventing text from wrapping beyond 5 lines and causing truncation with "...". For TextField to scroll instead of truncate, we need to allow more lines and add a height constraint.

# Test Case 2:
- The Text input showing max height, when no Keyboard showing.
- When keyboard is showing, Still get "..." when I enter long texts without enter line break 

# Test Case 3:
- [Failed] The Text input showing max height, when no Keyboard showing.
- [Passed] When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Passed] When keyboard is showing, height was increase to max line
- [Failed] When keyboard is showing, height was increase to max line BUT cannot scrolling vertical.
- [Failed] After hide the keyboard, I cannot click to the Text Input to show keyboard?

# Test Case 4:
- [Failed] The Text input showing max height, when no Keyboard showing.
- [Passed] When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Failed] When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text.
- [Failed] When keyboard is showing, height was increase to max line
- [Failed] When keyboard is showing, height was increase to max line BUT cannot scrolling vertical.
- [Passed] After hide the keyboard, I cannot click to the Text Input to show keyboard?

# Test Case 5 (Old):
- [Failed] 1. The Text input showing max height, when no Keyboard showing.
- [Passed] 2. When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Passed] 3. When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text.
- [Passed] 4. When keyboard is showing, height was increase to max line
- [Failed] 5. When keyboard is showing, height was increase to max line BUT cannot scrolling vertical.
- [Failed] 6. After hide the keyboard, I cannot click to the Text Input to show keyboard?
- [Failed] 7. The same root cause of #6, if losing focus to Text Input, then cannot click back to it to show keyboard for input texts

# Test Case 6 (Old):
- [Failed] 1. The Text input showing max height, when no Keyboard showing.
- [Passed] 2. When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Failed] 3. When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text.
- [Failed] 4. When keyboard is showing, height was increase to max line if typing texts and reach max lines.
- [Failed] 5. When keyboard is showing, height was increase to max line BUT cannot scrolling vertical.
- [Failed] 6. After hide the keyboard, I cannot click to the Text Input to show keyboard?
- [Failed] 7. The same root cause of #6, if losing focus to Text Input, then cannot click back to it to show keyboard for input texts

# Test Case 7 (New):
- [Passed] 1. The Text input showing max height, when no Keyboard showing.
- [Passed] 2. When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Failed] 3. When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text.
- [Passed] 3.1 This issue now turned into that the text input is showing 2 lines and cannot SCROLL any more.
- [Passed] 4. When keyboard is showing, height was increase to max line if typing texts and reach max lines.
- [Failed] 5. When keyboard is showing, height was increase to max line BUT cannot scrolling vertical. (#4 failed so lead to failed #5)
- [Failed] 6. After hide the keyboard, I cannot click to the Text Input to show keyboard?
            => Only possible to click back to the Text Input, if the texts have no "ultrathink" word, otherwise, cannot click
- [Failed] 7. The same root cause of #6, if losing focus to Text Input, then cannot click back to it to show keyboard for input texts


# Test Case 8 (New):
- [Passed] 1. The Text input showing max height, when no Keyboard showing.
- [Passed] 2. When keyboard is showing, Still get "..." when I enter long texts without enter line break 
- [Failed] 3. When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text.
- [Passed] 3.1 This issue now turned into that the text input is showing 2 lines and cannot SCROLL any more.
- [Passed] 4. When keyboard is showing, height was increase to max line if typing texts and reach max lines.
- [Failed] 5. When keyboard is showing, height was increase to max line BUT cannot scrolling vertical. (#4 failed so lead to failed #5)
- [Failed] 6. After hide the keyboard, I cannot click to the Text Input to show keyboard?
            => Only possible to click back to the Text Input, if the texts have no "ultrathink" word, otherwise, cannot click
- [Failed] 7. The same root cause of #6, if losing focus to Text Input, then cannot click back to it to show keyboard for input texts


# Test Case 8 (New):
- [Failed] 1. The Text input showing max height, when no Keyboard showing. -> Expected: Text Input show single line when no Keyboar showing.
- [Passed] 2. When keyboard is showing, Still get "..." when I enter long texts without enter line break -> Expected: Texts should break words when typing long texts over the textbox.
- [Failed] 3. When keyboard is showing, Still get "..." when I enter long texts without enter line break, there are some "ultrathink" words in the text and cannot SCROLL any more. -> Expected: Texts should break words when typing long texts over the textbox that's similar behavior of #2.
- [Passed] 3.1 This issue now turned into that the text input is showing 2 lines and cannot SCROLL any more. -> Expected: Text Input should increase height accordingly when text length is growing.
- [Failed] 4. When keyboard is showing, height was increase to max line if typing texts and reach max lines, it's now showing "..." at the end. Expected: The texts should be wrapped words and break lines, the text input should increase height accordingly.
- [Failed] 5. When keyboard is showing, height was increase to max line BUT cannot scrolling vertical. (#4 failed so lead to failed #5)
- [Failed] 6. After hide the keyboard, I cannot click to the Text Input to show keyboard. Only possible to click back to the Text Input, if the texts have no "ultrathink" word, otherwise, cannot click.
- [Failed] 7. The same root cause of #6, if losing focus to Text Input, then cannot click back to it to show keyboard for input texts
- [Failed] 8. why height of the Chat Input was not increase when I input super long text or press enter to break lines 