import { useEffect, type ReactNode } from "react";

/** Centered dialog on desktop, bottom sheet on phones. Closes on scrim click or Escape. */
export function Modal({ children, onClose, label }: { children: ReactNode; onClose: () => void; label: string }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="card lg modal" role="dialog" aria-modal="true" aria-label={label}>
        {children}
      </div>
    </div>
  );
}
