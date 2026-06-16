-- Styles the mounted Holler DMG: window size, background picture, icon layout.
-- Coordinates match Support/dmg-background.png (a 600x400-point window).
-- Finder is flaky about persisting geometry, so we set everything, force a
-- save with close → open, then re-assert bounds AND positions before the
-- final close — setting one without the other resets the other.
on run argv
	set volName to item 1 of argv
	if (count of argv) > 1 then
		set appName to item 2 of argv
	else
		set appName to volName
	end if
	set winBounds to {200, 120, 800, 520}
	set appPos to {165, 205}
	set appsPos to {435, 205}
	tell application "Finder"
		activate
		tell disk volName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to winBounds
			set theViewOptions to the icon view options of container window
			set arrangement of theViewOptions to not arranged
			set icon size of theViewOptions to 100
			set background picture of theViewOptions to file ".background:background.png"
			set position of item (appName & ".app") of container window to appPos
			set position of item "Applications" of container window to appsPos
			close
			open
			delay 1
			set position of item (appName & ".app") of container window to appPos
			set position of item "Applications" of container window to appsPos
			set the bounds of container window to winBounds
			delay 1
			set the bounds of container window to winBounds
			update without registering applications
			delay 2
			close
		end tell
	end tell
end run
