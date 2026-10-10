import { NavLink } from "react-router-dom";
import { ListMusic, Map as MapIcon, Navigation } from "lucide-react";
import { useStore } from "../state/store";

const TABS = [
  { to: "/map", title: "map", icon: MapIcon, fill: "var(--green)" },
  { to: "/playlist", title: "playlist", icon: ListMusic, fill: "var(--orange)" },
  { to: "/tracker", title: "tracker", icon: Navigation, fill: "var(--light-blue)" },
] as const;

/** Floating bar: white, 2px border, 4px hard shadow. The selected tab is a filled pill. */
export function TabBar() {
  const { newCount } = useStore();
  return (
    <nav className="tabbar card lg" aria-label="Main">
      {TABS.map(({ to, title, icon: Icon, fill }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) => `tab ${isActive ? "active" : ""}`}
          style={({ isActive }) => (isActive ? { background: fill } : undefined)}
          aria-label={title}
        >
          <Icon size={18} strokeWidth={2.25} aria-hidden />
          <span className="tab-title">{title}</span>
          {to === "/playlist" && newCount > 0 && <span className="badge">{newCount}</span>}
        </NavLink>
      ))}
    </nav>
  );
}
