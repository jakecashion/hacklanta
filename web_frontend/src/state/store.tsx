import { createContext, useContext, useMemo, useRef, useState, type ReactNode } from "react";
import {
  SONGS,
  nearbyUsers,
  sampleRecommendations,
  type BlockedUser,
  type NearbyUser,
  type Recommendation,
} from "../data/mock";

// In-memory mock store (stands in for MatchStore / RecommendationStore / BlockStore).
// Nothing persists and nothing hits the backend yet.

interface Actions {
  isBlocked: (id: string) => boolean;
  block: (id: string, name: string) => void;
  unblock: (id: string) => void;
  markRead: (id: string) => void;
  markAllRead: () => void;
  deleteRecommendation: (id: string) => void;
  addSamples: () => void;
  receiveSong: (userId: string) => void;
  clearRecommendations: () => void;
  resetBlocks: () => void;
}

interface Store extends Actions {
  users: NearbyUser[];
  visibleUsers: NearbyUser[];
  recommendations: Recommendation[];
  newCount: number;
  blocked: BlockedUser[];
}

const StoreContext = createContext<Store | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const [users] = useState(() => nearbyUsers());
  const [recommendations, setRecommendations] = useState<Recommendation[]>(() => sampleRecommendations());
  const [blocked, setBlocked] = useState<BlockedUser[]>([]);

  // Actions are created once so they are safe in effect dependency arrays.
  // They read the latest blocked list through a ref instead of closing over state.
  const blockedRef = useRef(blocked);
  blockedRef.current = blocked;

  const actions = useMemo<Actions>(() => {
    const isBlocked = (id: string) => blockedRef.current.some((b) => b.id === id);
    return {
      isBlocked,
      block: (id, name) => {
        setBlocked((b) => (b.some((x) => x.id === id) ? b : [{ id, name, blockedAt: Date.now() }, ...b]));
        // Blocking also removes everything they sent.
        setRecommendations((r) => r.filter((x) => x.senderId !== id));
      },
      unblock: (id) => setBlocked((b) => b.filter((x) => x.id !== id)),
      // Return the same array when nothing changes so a no-op does not re-render.
      markRead: (id) =>
        setRecommendations((r) =>
          r.some((x) => x.id === id && x.isNew) ? r.map((x) => (x.id === id ? { ...x, isNew: false } : x)) : r,
        ),
      markAllRead: () =>
        setRecommendations((r) => (r.some((x) => x.isNew) ? r.map((x) => ({ ...x, isNew: false })) : r)),
      deleteRecommendation: (id) => setRecommendations((r) => r.filter((x) => x.id !== id)),
      addSamples: () => setRecommendations(sampleRecommendations().filter((x) => !isBlocked(x.senderId))),
      receiveSong: (userId) => {
        const sender = users.find((u) => u.id === userId);
        if (!sender || isBlocked(userId)) return;
        const notes = ["you will love this one", "reminded me of you", "on repeat all week", ""];
        setRecommendations((r) => [
          {
            id: `r-${Date.now()}`,
            song: SONGS[Math.floor(Math.random() * SONGS.length)],
            senderId: sender.id,
            senderName: sender.name,
            note: notes[Math.floor(Math.random() * notes.length)],
            sharedGenres: sender.sharedGenres,
            receivedAt: Date.now(),
            isNew: true,
          },
          ...r,
        ]);
      },
      clearRecommendations: () => setRecommendations([]),
      resetBlocks: () => setBlocked([]),
    };
  }, [users]);

  const value = useMemo<Store>(
    () => ({
      ...actions,
      users,
      visibleUsers: users.filter((u) => !blocked.some((b) => b.id === u.id)),
      recommendations,
      newCount: recommendations.filter((r) => r.isNew).length,
      blocked,
    }),
    [actions, users, recommendations, blocked],
  );

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore(): Store {
  const ctx = useContext(StoreContext);
  if (!ctx) throw new Error("useStore must be used inside <StoreProvider>");
  return ctx;
}
