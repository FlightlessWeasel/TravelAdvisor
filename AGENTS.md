# TravelAdvisor repository notes

## Local Retail deployment

The live Retail WoW addon directory is:

`D:\Battle.net\World of Warcraft\_retail_\Interface\AddOns\TravelAdvisor`

Deploy the runtime addon files from this repository's root:

- `TravelAdvisor.toc`
- `TravelAdvisor.lua`
- `TravelAdvisorSettings.lua`
- `TravelData.lua`
- `TravelGraph.lua`
- `TravelSources.lua`
- `Libs\`

Keep repository tests, tools, documentation, and Git metadata out of the installed addon directory. After deployment, verify the target files match the source files before testing in-game.

<!-- BEGIN init-wow-addon managed block -->
## WoW addon instructions

- Addon: `TravelAdvisor`
- Author: `jason`
- WoW target: `mainline`
- TOC interface: `120100`
- Verified install/test path: `D:\Battle.net\World of Warcraft\_retail_\Interface\AddOns`
- Repo-local MCP config: `<addon>/.codex/config.toml`

### Sources and correctness

- Use Context7 MCP for Lua language, standard-library, and library information.
- Use the connected Hated WoW MCP for WoW API information, events, frames, TOC/interface correctness, and client-specific behavior. Report a missing connection instead of guessing.
- Use web search tools to find and verify item, NPC, spell, quest, news, and live-event data on `wowhead.com`.
- Revalidate the cached install/test path before copying or deploying the addon.

### User interface

- Slash commands may exist, but every option and work path must also have an in-game UI option.

### Debug output

- Keep debug data structured and bounded; do not dump millions of variables.
- Copyable debug information must include a concise prompt for the agent together with the debug data.
- Present copyable debug data in a window with Select All and Close buttons. Exclude credentials and unrelated addon data.
<!-- END init-wow-addon managed block -->
