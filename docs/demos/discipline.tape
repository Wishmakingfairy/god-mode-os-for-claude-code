# god-mode-os: Discipline tier hero demo (v2)
# Real hook on a simulated session. Shows the lie, the block, and the rewrite.
# Renders docs/demos/discipline.gif

Output docs/demos/discipline.gif

Set Theme "Catppuccin Mocha"
Set FontSize 16
Set FontFamily "JetBrains Mono"
Set Width 1200
Set Height 720
Set Padding 24
Set TypingSpeed 18ms
Set PlaybackSpeed 1.0

Hide
Type "clear"
Enter
Show

Sleep 400ms
Type "bash docs/demos/fixtures/simulated-session.sh"
Sleep 400ms
Enter

# The script runs: prints user + assistant turns, fires real hook,
# shows BLOCK, then rewrite with tool use, ending in green pass.
Sleep 18s
