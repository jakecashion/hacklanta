// Mock data, ported from Models.swift `MockData`. Replace with backend calls later.

export interface Song {
  id: string;
  title: string;
  artist: string;
  artworkURL?: string;
}

export interface NearbyUser {
  id: string;
  name: string;
  distanceMeters: number;
  nowPlaying?: Song;
  sharedGenres: string[];
  lat: number;
  lng: number;
}

export interface Recommendation {
  id: string;
  song: Song;
  senderId: string;
  senderName: string;
  note: string;
  sharedGenres: string[];
  receivedAt: number; // epoch ms
  isNew: boolean;
}

export interface BlockedUser {
  id: string;
  name: string;
  blockedAt: number;
}

export const SELF_ID = "me";

/** Georgia State University campus, same as the seeded backend sessions. */
export const DEFAULT_CENTER: [number, number] = [33.7531, -84.3858];

export const SONGS: Song[] = [
  { id: "s1", title: "Garden Song", artist: "Phoebe Bridgers" },
  { id: "s2", title: "Slow Burn", artist: "Kacey Musgraves" },
  { id: "s3", title: "Alison", artist: "Slowdive" },
  { id: "s4", title: "Cherry-coloured Funk", artist: "Cocteau Twins" },
  { id: "s5", title: "Dress", artist: "Wednesday" },
  { id: "s6", title: "Motion Sickness", artist: "Phoebe Bridgers" },
];

export function searchSongs(query: string): Song[] {
  const q = query.toLowerCase();
  return SONGS.filter((s) => s.title.toLowerCase().includes(q) || s.artist.toLowerCase().includes(q));
}

const METERS_PER_DEGREE = 111_320;

/** Four mock people at fixed offsets (north, east in meters) from the center. */
export function nearbyUsers(center: [number, number] = DEFAULT_CENTER): NearbyUser[] {
  const people: { id: string; name: string; north: number; east: number; song?: Song; genres: string[] }[] = [
    { id: "u-maya", name: "Maya", north: 40, east: 30, song: SONGS[5], genres: ["indie rock", "shoegaze", "bedroom pop"] },
    { id: "u-dev", name: "Dev", north: -120, east: 90, song: SONGS[2], genres: ["shoegaze", "dream pop"] },
    { id: "u-sam", name: "Sam", north: 180, east: -150, song: SONGS[4], genres: ["indie rock"] },
    { id: "u-lee", name: "Lee", north: -260, east: -300, genres: ["bedroom pop"] },
  ];
  return people.map((p) => ({
    id: p.id,
    name: p.name,
    distanceMeters: Math.hypot(p.north, p.east),
    nowPlaying: p.song,
    sharedGenres: p.genres,
    lat: center[0] + p.north / METERS_PER_DEGREE,
    lng: center[1] + p.east / (METERS_PER_DEGREE * Math.cos((center[0] * Math.PI) / 180)),
  }));
}

export function sampleRecommendations(): Recommendation[] {
  const now = Date.now();
  const users = nearbyUsers();
  const mk = (i: number, userIdx: number, song: Song, note: string, agoMin: number, isNew: boolean): Recommendation => ({
    id: `r-${i}`,
    song,
    senderId: users[userIdx].id,
    senderName: users[userIdx].name,
    note,
    sharedGenres: users[userIdx].sharedGenres,
    receivedAt: now - agoMin * 60_000,
    isNew,
  });
  return [
    mk(1, 0, SONGS[0], "this one reminds me of you", 2, true),
    mk(2, 1, SONGS[3], "", 45, true),
    mk(3, 2, SONGS[1], "saw you were into this", 60 * 26, false),
  ];
}

/** Rounds to the nearest 10 m. Under 20 m: "right next to you". */
export function distanceText(meters: number): string {
  if (meters < 20) return "right next to you";
  return `${Math.round(meters / 10) * 10} m away`;
}

export function relativeTime(epochMs: number): string {
  const diffSec = (Date.now() - epochMs) / 1000;
  if (diffSec < 60) return "just now";
  const rtf = new Intl.RelativeTimeFormat("en", { numeric: "always" });
  if (diffSec < 3600) return rtf.format(-Math.round(diffSec / 60), "minute");
  if (diffSec < 86400) return rtf.format(-Math.round(diffSec / 3600), "hour");
  return rtf.format(-Math.round(diffSec / 86400), "day");
}
