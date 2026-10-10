import type { ReactNode } from "react";
import { Outlet, useNavigate } from "react-router-dom";
import { ArrowLeft, X } from "lucide-react";
import { TabBar } from "./TabBar";

/** Main app shell: routed content plus the floating tab bar. */
export function TabLayout() {
  return (
    <>
      <Outlet />
      <TabBar />
    </>
  );
}

/** Match flow shell (the iOS full-screen cover): no tab bar, a close button, a back button past the first screen. */
export function MatchLayout() {
  return (
    <div className="page">
      <Outlet />
    </div>
  );
}

/** Sticky top bar for pushed screens: white with an ink line, like the iOS nav bar. */
export function TopBar({
  title,
  back = true,
  close = false,
  right,
}: {
  title?: string;
  back?: boolean;
  close?: boolean;
  right?: ReactNode;
}) {
  const navigate = useNavigate();
  return (
    <header className="topbar">
      <div className="topbar-side">
        {back && (
          <button type="button" className="nav-btn" onClick={() => navigate(-1)} aria-label="Back">
            <ArrowLeft size={22} strokeWidth={2.5} />
          </button>
        )}
      </div>
      <h3 className="topbar-title">{title}</h3>
      <div className="topbar-side end">
        {right}
        {close && (
          <button type="button" className="nav-btn" onClick={() => navigate("/map")} aria-label="Close">
            <X size={22} strokeWidth={2.5} />
          </button>
        )}
      </div>
    </header>
  );
}
