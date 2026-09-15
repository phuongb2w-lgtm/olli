import type { SupabaseClient } from "@supabase/supabase-js";
import type { RoomStatus } from "./constants";

export type RoomListItem = {
  id: string;
  name: string;
  code: string | null;
  capacity: number | null;
  status: RoomStatus;
};

export async function fetchRoomList(supabase: SupabaseClient): Promise<RoomListItem[]> {
  const { data, error } = await supabase
    .from("room")
    .select("id, name, code, capacity, status")
    .order("name");
  if (error || !data) return [];
  return data.map((row) => ({
    id: row.id,
    name: row.name,
    code: row.code,
    capacity: row.capacity,
    status: row.status as RoomStatus,
  }));
}

export async function fetchRoomById(
  supabase: SupabaseClient,
  roomId: string,
): Promise<RoomListItem | null> {
  const { data, error } = await supabase
    .from("room")
    .select("id, name, code, capacity, status")
    .eq("id", roomId)
    .maybeSingle();
  if (error || !data) return null;
  return {
    id: data.id,
    name: data.name,
    code: data.code,
    capacity: data.capacity,
    status: data.status as RoomStatus,
  };
}
