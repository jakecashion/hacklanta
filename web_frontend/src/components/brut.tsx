import type { ButtonHTMLAttributes, CSSProperties, ElementType, ReactNode } from "react";
import { Music } from "lucide-react";

// Shared neobrutalist primitives, ported from Theme.swift.
// Colours are CSS variables (src/theme.css); components take the colour name.

export type Accent = "red" | "blue" | "green" | "yellow" | "orange" | "light-blue" | "surface" | "ink";

const fillVar = (c: Accent) => (c === "surface" ? "var(--surface)" : `var(--${c})`);

/** Outlined or filled pill tag. */
export function GenreChip({ text, fill = "yellow", xs = false }: { text: string; fill?: "yellow" | "surface" | "green" | "orange" | "red"; xs?: boolean }) {
  return <span className={`chip ${fill === "yellow" ? "" : fill} ${xs ? "xs" : ""}`}>{text}</span>;
}

/** Line icon in a pastel circle with a small hard shadow. Pass `onClick` to make it a button. */
export function IconBox({
  icon: Icon,
  fill = "green",
  size = 48,
  onClick,
  label,
}: {
  icon: ElementType;
  fill?: Accent;
  size?: number;
  onClick?: () => void;
  label?: string;
}) {
  const style = { "--size": `${size}px`, "--fill": fillVar(fill) } as CSSProperties;
  const icon = <Icon size={Math.round(size * 0.46)} strokeWidth={2} aria-hidden />;
  if (onClick) {
    return (
      <button type="button" className="icon-box button" style={style} onClick={onClick} aria-label={label}>
        {icon}
      </button>
    );
  }
  return (
    <span className="icon-box" style={style} aria-hidden={label ? undefined : true} aria-label={label}>
      {icon}
    </span>
  );
}

export function CoverArt({ url, size = 72, round = false }: { url?: string; size?: number; round?: boolean }) {
  return (
    <span className={`cover ${round ? "round" : ""}`} style={{ "--size": `${size}px` } as CSSProperties}>
      {url ? <img src={url} alt="" /> : <Music size={Math.round(size * 0.4)} aria-hidden />}
    </span>
  );
}

export function Equalizer() {
  return (
    <span className="eq" aria-hidden>
      <i /><i /><i /><i />
    </span>
  );
}

/** Four-point star on a 32x32 grid. Waist is wider than FourPointStar in Theme.swift (17.5/14.5 there)
 *  so the fill stays visible under the 1.5px outline at web sizes. */
export function DecorStar({
  color = "yellow",
  size = 28,
  rotation = 0,
  style,
}: {
  color?: Accent;
  size?: number;
  rotation?: number;
  style?: CSSProperties;
}) {
  return (
    <svg
      className="decor"
      width={size}
      height={size}
      viewBox="0 0 32 32"
      style={{ transform: `rotate(${rotation}deg)`, ...style }}
      aria-hidden
    >
      <polygon
        points="16,2 20,12 30,16 20,20 16,30 12,20 2,16 12,12"
        style={{ fill: fillVar(color), stroke: "var(--ink)" }}
        strokeWidth={1.5}
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

export function DecorBlob({ color = "orange", size = 56, style }: { color?: Accent; size?: number; style?: CSSProperties }) {
  return (
    <span
      className="decor blob"
      style={{ width: size, height: size * 0.86, background: fillVar(color), ...style }}
      aria-hidden
    />
  );
}

/** Press-down button. Variants map to the .brutPrimary / Secondary / Ghost / Pill styles. */
export function Button({
  variant = "primary",
  auto = false,
  small = false,
  icon: Icon,
  children,
  className = "",
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "green" | "pill";
  auto?: boolean;
  small?: boolean;
  icon?: ElementType;
}) {
  const v = variant === "primary" ? "" : variant === "pill" ? "pill" : variant;
  return (
    <button type="button" className={`btn ${v} ${auto ? "auto" : ""} ${small ? "sm" : ""} ${className}`} {...rest}>
      {Icon && <Icon size={18} strokeWidth={2.25} aria-hidden />}
      {children}
    </button>
  );
}

export function Card({
  children,
  flat = false,
  large = false,
  className = "",
  style,
}: {
  children: ReactNode;
  flat?: boolean;
  large?: boolean;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <div className={`card ${flat ? "flat" : ""} ${large ? "lg" : ""} ${className}`} style={style}>
      {children}
    </div>
  );
}

/** Empty-state block: stars around a big icon, heavy title, muted body. */
export function EmptyState({
  icon,
  iconFill = "light-blue",
  starColor = "orange",
  title,
  body,
}: {
  icon: ElementType;
  iconFill?: Accent;
  starColor?: Accent;
  title: string;
  body: string;
}) {
  return (
    <div className="empty">
      <div className="empty-art">
        <DecorStar color="yellow" size={30} rotation={10} style={{ left: -62, top: -22 }} />
        <DecorStar color={starColor} size={20} rotation={-10} style={{ right: -62, top: -30 }} />
        <IconBox icon={icon} fill={iconFill} size={72} />
      </div>
      <h2>{title}</h2>
      <p className="muted">{body}</p>
    </div>
  );
}
