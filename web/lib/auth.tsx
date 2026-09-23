"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { api, setToken } from "@/lib/api";
import type { Profile, Role } from "@/lib/types";

type AuthState = {
  user: Profile | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  /** `can("admin")` — the same names the API's role middleware uses. */
  can: (...roles: Role[]) => boolean;
  /** Everyone who works here, as opposed to a family reading their file. */
  isStaff: boolean;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  /*
   * The profile is re-fetched on load rather than cached alongside the token.
   * A role stored in localStorage is a role the user can edit; asking the
   * server means the menu can never show more than the token actually opens.
   */
  useEffect(() => {
    let cancelled = false;

    api<{ data: Profile }>("/auth/me")
      .then((res) => {
        if (!cancelled) setUser(res.data);
      })
      .catch(() => {
        if (!cancelled) setUser(null);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    const res = await api<{ token: string; data: Profile }>("/auth/login", {
      method: "POST",
      body: { email, password },
    });

    setToken(res.token);
    setUser(res.data);
  }, []);

  const signOut = useCallback(async () => {
    // The server call is best-effort: if it fails the local token still goes,
    // and a signed-out user staring at a child's file is the worse outcome.
    try {
      await api("/auth/logout", { method: "POST" });
    } catch {
      /* nothing to do about it */
    }

    setToken(null);
    setUser(null);
  }, []);

  const can = useCallback(
    (...roles: Role[]) => (user ? roles.includes(user.role) : false),
    [user],
  );

  return (
    <AuthContext.Provider
      value={{ user, loading, signIn, signOut, can, isStaff: user?.is_staff ?? false }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error("useAuth outside AuthProvider");
  }

  return context;
}
