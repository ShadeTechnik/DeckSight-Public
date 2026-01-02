
import { findModuleChild } from "@decky/ui";
import { 
    FunctionComponent,
    useState,
    useEffect
} from "react";
import {
    addEventListener,
    removeEventListener
} from '@decky/api';

enum UIComposition {
  Hidden = 0,
  Notification = 1,
  Overlay = 2,
  Opaque = 3,
  OverlayKeyboard = 4,
}

type UseUIComposition = (composition: UIComposition) => {
  releaseComposition: () => void;
};

const useUIComposition: UseUIComposition = findModuleChild((m) => {
  if (typeof m !== "object") return undefined;
  for (let prop in m) {
    if (
      typeof m[prop] === "function" &&
      m[prop].toString().includes("AddMinimumCompositionStateRequest") &&
      m[prop].toString().includes("ChangeMinimumCompositionStateRequest") &&
      m[prop].toString().includes("RemoveMinimumCompositionStateRequest") &&
      !m[prop].toString().includes("m_mapCompositionStateRequests")
    ) {
      return m[prop];
    }
  }
});

const UICompositionProxy: FunctionComponent = () => {
  useUIComposition(UIComposition.Notification);
  return null;
};

const Overlay = ({ initialOpacity = 0, backgroundColor = 'black' }) => {
const [opacity, setOpacity] = useState(initialOpacity);

  useEffect(() => {
    const listener = (brightness: number) => {
        setOpacity(1 - brightness)
    };

    addEventListener("brightness_change", listener);

    return () => {
      removeEventListener("brightness_change", listener);
    };
  }, []);

  return (<div
    id="brightness_bar_container"
    style={{
      left: 0,
      top: 0,
      width: "100vw",
      height: "100vh",
      background: backgroundColor,
      zIndex: 7001, // volume bar is 7000
      position: "fixed",
      opacity,
      pointerEvents: "none",
      transition: "opacity 0.15s linear"
    }}
  >
    <UICompositionProxy />
  </div>)
};

export default Overlay;