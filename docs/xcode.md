are you able to launch the app from xcode? And when it's running can you find the pid and kill it so you can make
  code changes, re-compile and launch it again?


• Yes.

  I can use the CLI loop:

  xcodebuild -project macos-app.xcodeproj -scheme macos-app -configuration Debug -destination 'platform=macOS' build
  open ~/Library/Developer/Xcode/DerivedData/macos-app-*/Build/Products/Debug/wkdomains.app
  pgrep -fl wkdomains
  kill <pid>

  So the workflow can be:

  1. Find/kill running wkdomains.
  2. Make code changes.
  3. Recompile with xcodebuild.
  4. Launch the rebuilt app.
  5. Hit localhost:9001 endpoints to verify.

  I can do that when needed.


› try a test it's not running now. launch it, kill it, make a small change  and re launch it


• I’ll run the full loop against the built app: launch the existing debug app, confirm the process/API, kill that
  process, make a tiny Swift UI text change, rebuild, and launch the rebuilt app.

• Ran app=$(ls -td ~/Library/Developer/Xcode/DerivedData/macos-app-*/Build/Products/Debug/wkdomains.app 2>/dev/null | h
  │ ead -n 1); if [ -z "$app" ]; then echo 'no built app found'; exit 1; fi; open "$app"; sleep 2; pgrep -fl wkdomain
  │ s; curl -sS --max-time 2 http://localhost:9001/api/v1/page | jq '{url,title,viewportMode}'
  └ 31882 npm exec wrangler dev --port 8787 --persist-to .wrangler/state NVM_INC=/Users/aa/.nvm/versions/node/v22.22.2/
    include/node TERM_PROGRAM=Apple_Terminal NODE=/Users/aa/.nvm/versions/node/v22.22.2/bin/node
    … +13 lines (ctrl + t to view transcript)
      "viewportMode": "desktop"
    }

• Waited for background terminal

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• The app launched and the local API responded on localhost:9001; the app process is PID 51455. I’ll kill only that app
  process now, then make a tiny code change.

• Ran pid=$(pgrep -x wkdomains | head -n 1); if [ -z "$pid" ]; then echo 'wkdomains not running'; exit 1; fi; kill
  │ "$pid"; sleep 1; if pgrep -x wkdomains >/dev/null; then echo 'still running'; pgrep -fl wkdomains; exit 1; fi;
  │ echo "killed $pid"
  └ killed 51455

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• I’m making a harmless Swift UI text change in the viewport help labels so there is an actual code delta to rebuild and
  relaunch.

• Edited macos-app/Browser/BrowserViewportMode.swift (+2 -2)
    54          case .mobileLarge:
    55 -            return "Mobile Large: 700px"
    55 +            return "Mobile Large: 700px wide"
    56          case .mobileSmall:
    57 -            return "Mobile Small: 390px"
    57 +            return "Mobile Small: 390px wide"
    58          }

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• The edit is in. I’m rebuilding with Xcode, then I’ll open the rebuilt debug app and confirm the PID/API again.

• Ran xcodebuild -project macos-app.xcodeproj -scheme macos-app -configuration Debug -destination 'platform=macOS' build
  └ Command line invocation:
        /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project macos-app.xcodeproj -scheme macos-app
    … +152 lines (ctrl + t to view transcript)
    ** BUILD SUCCEEDED **


• Context compacted

• Waited for background terminal

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• I’ve already launched the debug app once, confirmed the local API responded, killed the exact wkdomains process, made
  a small Swift UI text change, and rebuilt successfully. I’m relaunching the rebuilt app now and checking that the API
  is reachable.

• Ran app=$(ls -td ~/Library/Developer/Xcode/DerivedData/macos-app-*/Build/Products/Debug/wkdomains.app 2>/dev/null |
  │ head -n 1)
  │ open "$app"
  │ … +3 lines
  └ 51545
    {
    … +2 lines (ctrl + t to view transcript)
      "viewportMode": "desktop"
    }

