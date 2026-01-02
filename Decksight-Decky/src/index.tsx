import { PanelSection, PanelSectionRow, ToggleField, staticClasses } from "@decky/ui"
import {
  definePlugin,
  routerHook,
  callable
} from "@decky/api"
import { useEffect, useState } from "react"
import Overlay from "./overlay"
import logo from "../assets/DS.png"
const startMonitor = callable<[], void>("start_monitor")
const getEnabled = callable<[], boolean>("get_enabled")
const setEnabled = callable<[boolean], boolean>("set_enabled")

function Content() {
  const [enabled, setEnabledState] = useState(true)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let active = true
    getEnabled()
      .then((value) => {
        if (active) setEnabledState(!!value)
      })
      .catch(() => {})
    return () => {
      active = false
    }
  }, [])

  const onToggle = async (value: boolean) => {
    setBusy(true)
    try {
      const next = await setEnabled(value)
      setEnabledState(!!next)
    } finally {
      setBusy(false)
    }
  }

  return (
    <PanelSection title="">
      <PanelSectionRow>
        <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
          <img src={logo} style={{ width: 200, height: "auto" }} />
        </div>
      </PanelSectionRow>
      <PanelSectionRow>
        <ToggleField
          label="Brightness Control"
          checked={enabled}
          disabled={busy}
          onChange={onToggle}
        />
      </PanelSectionRow>
    </PanelSection>
  )
}

export default definePlugin(() => {
  routerHook.addGlobalComponent("BrightnessOverlay", (props) => <Overlay {...props} />)
  getEnabled()
    .then((enabled) => {
      if (enabled) startMonitor()
    })
    .catch(() => {
      startMonitor()
    })
  return {
    name: "DeckSight",
    titleView: <div className={staticClasses.Title}>DeckSight</div>,
    content: <Content />,
    icon: <img src={logo} style={{ height: 20, width: "auto" }} />,
    onDismount() {
      routerHook.removeGlobalComponent('BrightnessOverlay')
    }
  }
})
