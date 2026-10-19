// BERKAS HASIL GENERATE — jangan diedit. Jalankan `pnpm db:types` setelah mengubah migration.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "audit_logs": {
                  Row: {
                    "action": string,"actor_id": string | null,"actor_kind": string,"after": Json | null,"before": Json | null,"created_at": string,"entity": string,"entity_id": string | null,"event_id": string | null,"id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_id"?: string | null,"actor_kind": string,"after"?: Json | null,"before"?: Json | null,"created_at"?: string,"entity": string,"entity_id"?: string | null,"event_id"?: string | null,"id"?: never
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"actor_kind"?: string,"after"?: Json | null,"before"?: Json | null,"created_at"?: string,"entity"?: string,"entity_id"?: string | null,"event_id"?: string | null,"id"?: never
                  }
                  Relationships: [
                    {
      foreignKeyName: "audit_logs_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"auth_attempts": {
                  Row: {
                    "created_at": string,"event_code": string | null,"event_id": string | null,"id": number,"ip": string | null,"kind": Database["public"]['Enums']["auth_attempt_kind"],"method": Database["public"]['Enums']["login_method"] | null,"reason": string | null,"success": boolean,"usher_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"event_code"?: string | null,"event_id"?: string | null,"id"?: never,"ip"?: string | null,"kind": Database["public"]['Enums']["auth_attempt_kind"],"method"?: Database["public"]['Enums']["login_method"] | null,"reason"?: string | null,"success": boolean,"usher_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"event_code"?: string | null,"event_id"?: string | null,"id"?: never,"ip"?: string | null,"kind"?: Database["public"]['Enums']["auth_attempt_kind"],"method"?: Database["public"]['Enums']["login_method"] | null,"reason"?: string | null,"success"?: boolean,"usher_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "auth_attempts_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "auth_attempts_usher_id_fkey"
      columns: ["usher_id"]
isOneToOne: false
      referencedRelation: "ushers"
      referencedColumns: ["id"]
    }
                  ]
                },"check_ins": {
                  Row: {
                    "actual_pax": number,"checked_in_at": string,"checked_out_at": string | null,"created_by": string | null,"device_id": string | null,"event_id": string,"guest_id": string | null,"id": string,"pending_guest": Json | null,"quarantine_reason": Database["public"]['Enums']["quarantine_reason"] | null,"received_at": string,"reviewed_at": string | null,"reviewed_by": string | null,"source": Database["public"]['Enums']["check_in_source"],"status": Database["public"]['Enums']["check_in_status"],"ticket_number": string | null,"updated_at": string,"usher_id": string | null,"void_reason": string | null,"voided_at": string | null,"voided_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "actual_pax": number,"checked_in_at": string,"checked_out_at"?: string | null,"created_by"?: string | null,"device_id"?: string | null,"event_id": string,"guest_id"?: string | null,"id": string,"pending_guest"?: Json | null,"quarantine_reason"?: Database["public"]['Enums']["quarantine_reason"] | null,"received_at"?: string,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"source": Database["public"]['Enums']["check_in_source"],"status": Database["public"]['Enums']["check_in_status"],"ticket_number"?: string | null,"updated_at"?: string,"usher_id"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Update: {
                    "actual_pax"?: number,"checked_in_at"?: string,"checked_out_at"?: string | null,"created_by"?: string | null,"device_id"?: string | null,"event_id"?: string,"guest_id"?: string | null,"id"?: string,"pending_guest"?: Json | null,"quarantine_reason"?: Database["public"]['Enums']["quarantine_reason"] | null,"received_at"?: string,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"source"?: Database["public"]['Enums']["check_in_source"],"status"?: Database["public"]['Enums']["check_in_status"],"ticket_number"?: string | null,"updated_at"?: string,"usher_id"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "check_ins_device_same_event"
      columns: ["event_id","device_id"]
isOneToOne: false
      referencedRelation: "devices"
      referencedColumns: ["event_id","id"]
    },{
      foreignKeyName: "check_ins_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "check_ins_guest_same_event"
      columns: ["event_id","guest_id"]
isOneToOne: false
      referencedRelation: "guests"
      referencedColumns: ["event_id","id"]
    },{
      foreignKeyName: "check_ins_usher_same_event"
      columns: ["event_id","usher_id"]
isOneToOne: false
      referencedRelation: "ushers"
      referencedColumns: ["event_id","id"]
    }
                  ]
                },"checkin_settings": {
                  Row: {
                    "allow_multi_checkin": boolean,"event_id": string,"print_entrusted_gift": NonNullable<Json>,"print_ticket": NonNullable<Json>,"show_verification": boolean,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "allow_multi_checkin"?: boolean,"event_id": string,"print_entrusted_gift"?: NonNullable<Json>,"print_ticket"?: NonNullable<Json>,"show_verification"?: boolean,"updated_at"?: string
                  }
                  Update: {
                    "allow_multi_checkin"?: boolean,"event_id"?: string,"print_entrusted_gift"?: NonNullable<Json>,"print_ticket"?: NonNullable<Json>,"show_verification"?: boolean,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "checkin_settings_event_id_fkey"
      columns: ["event_id"]
isOneToOne: true
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"devices": {
                  Row: {
                    "app_version": string | null,"auth_user_deleted_at": string | null,"auth_user_id": string | null,"clock_offset_ms": number | null,"code": string,"created_at": string,"event_id": string,"id": string,"last_seen_at": string | null,"name": string | null,"revoke_mode": Database["public"]['Enums']["revoke_mode"] | null,"revoke_reason": string | null,"revoked_at": string | null,"revoked_by": string | null,"session_expires_at": string,"usher_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "app_version"?: string | null,"auth_user_deleted_at"?: string | null,"auth_user_id"?: string | null,"clock_offset_ms"?: number | null,"code": string,"created_at"?: string,"event_id": string,"id": string,"last_seen_at"?: string | null,"name"?: string | null,"revoke_mode"?: Database["public"]['Enums']["revoke_mode"] | null,"revoke_reason"?: string | null,"revoked_at"?: string | null,"revoked_by"?: string | null,"session_expires_at": string,"usher_id": string
                  }
                  Update: {
                    "app_version"?: string | null,"auth_user_deleted_at"?: string | null,"auth_user_id"?: string | null,"clock_offset_ms"?: number | null,"code"?: string,"created_at"?: string,"event_id"?: string,"id"?: string,"last_seen_at"?: string | null,"name"?: string | null,"revoke_mode"?: Database["public"]['Enums']["revoke_mode"] | null,"revoke_reason"?: string | null,"revoked_at"?: string | null,"revoked_by"?: string | null,"session_expires_at"?: string,"usher_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "devices_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "devices_usher_same_event"
      columns: ["event_id","usher_id"]
isOneToOne: false
      referencedRelation: "ushers"
      referencedColumns: ["event_id","id"]
    }
                  ]
                },"event_members": {
                  Row: {
                    "created_at": string,"event_id": string,"role": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"event_id": string,"role"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"event_id"?: string,"role"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "event_members_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"events": {
                  Row: {
                    "archived_at": string | null,"attendance_limit": number | null,"code": string,"couple_names": string | null,"created_at": string,"created_by": string | null,"event_date": string,"id": string,"name": string,"settings": NonNullable<Json>,"timezone": string,"updated_at": string,"venue": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"attendance_limit"?: number | null,"code"?: string,"couple_names"?: string | null,"created_at"?: string,"created_by"?: string | null,"event_date": string,"id"?: string,"name": string,"settings"?: NonNullable<Json>,"timezone"?: string,"updated_at"?: string,"venue"?: string | null
                  }
                  Update: {
                    "archived_at"?: string | null,"attendance_limit"?: number | null,"code"?: string,"couple_names"?: string | null,"created_at"?: string,"created_by"?: string | null,"event_date"?: string,"id"?: string,"name"?: string,"settings"?: NonNullable<Json>,"timezone"?: string,"updated_at"?: string,"venue"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"greeting_configs": {
                  Row: {
                    "category": Database["public"]['Enums']["guest_category"],"event_id": string,"popup": NonNullable<Json>,"screen": NonNullable<Json>,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "category": Database["public"]['Enums']["guest_category"],"event_id": string,"popup"?: NonNullable<Json>,"screen"?: NonNullable<Json>,"updated_at"?: string
                  }
                  Update: {
                    "category"?: Database["public"]['Enums']["guest_category"],"event_id"?: string,"popup"?: NonNullable<Json>,"screen"?: NonNullable<Json>,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "greeting_configs_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"guest_groups": {
                  Row: {
                    "created_at": string,"deleted_at": string | null,"description": string | null,"event_id": string,"id": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deleted_at"?: string | null,"description"?: string | null,"event_id": string,"id"?: string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"deleted_at"?: string | null,"description"?: string | null,"event_id"?: string,"id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "guest_groups_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"guests": {
                  Row: {
                    "attendance_status": Database["public"]['Enums']["attendance_status"],"category": Database["public"]['Enums']["guest_category"],"created_at": string,"created_device_id": string | null,"deleted_at": string | null,"event_id": string,"group_id": string | null,"id": string,"invited_pax": number,"is_additional": boolean,"name": string,"notes": string | null,"phone": string | null,"qr_token": string,"qr_token_hash": string,"rsvp_pax": number | null,"rsvp_status": Database["public"]['Enums']["rsvp_status"],"special_number": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attendance_status"?: Database["public"]['Enums']["attendance_status"],"category"?: Database["public"]['Enums']["guest_category"],"created_at"?: string,"created_device_id"?: string | null,"deleted_at"?: string | null,"event_id": string,"group_id"?: string | null,"id"?: string,"invited_pax"?: number,"is_additional"?: boolean,"name": string,"notes"?: string | null,"phone"?: string | null,"qr_token"?: string,"qr_token_hash"?: never,"rsvp_pax"?: number | null,"rsvp_status"?: Database["public"]['Enums']["rsvp_status"],"special_number"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "attendance_status"?: Database["public"]['Enums']["attendance_status"],"category"?: Database["public"]['Enums']["guest_category"],"created_at"?: string,"created_device_id"?: string | null,"deleted_at"?: string | null,"event_id"?: string,"group_id"?: string | null,"id"?: string,"invited_pax"?: number,"is_additional"?: boolean,"name"?: string,"notes"?: string | null,"phone"?: string | null,"qr_token"?: string,"qr_token_hash"?: never,"rsvp_pax"?: number | null,"rsvp_status"?: Database["public"]['Enums']["rsvp_status"],"special_number"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "guests_created_device_same_event"
      columns: ["event_id","created_device_id"]
isOneToOne: false
      referencedRelation: "devices"
      referencedColumns: ["event_id","id"]
    },{
      foreignKeyName: "guests_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "guests_group_same_event"
      columns: ["event_id","group_id"]
isOneToOne: false
      referencedRelation: "guest_groups"
      referencedColumns: ["event_id","id"]
    }
                  ]
                },"ticket_number_settings": {
                  Row: {
                    "category": Database["public"]['Enums']["guest_category"],"digits": number,"event_id": string,"prefix": string,"start_number": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "category": Database["public"]['Enums']["guest_category"],"digits"?: number,"event_id": string,"prefix": string,"start_number"?: number,"updated_at"?: string
                  }
                  Update: {
                    "category"?: Database["public"]['Enums']["guest_category"],"digits"?: number,"event_id"?: string,"prefix"?: string,"start_number"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ticket_number_settings_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                },"usher_login_tokens": {
                  Row: {
                    "created_at": string,"created_by": string,"expires_at": string,"id": string,"token_hash": string,"used_at": string | null,"usher_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by": string,"expires_at": string,"id"?: string,"token_hash": string,"used_at"?: string | null,"usher_id": string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string,"expires_at"?: string,"id"?: string,"token_hash"?: string,"used_at"?: string | null,"usher_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "usher_login_tokens_usher_id_fkey"
      columns: ["usher_id"]
isOneToOne: false
      referencedRelation: "ushers"
      referencedColumns: ["id"]
    }
                  ]
                },"ushers": {
                  Row: {
                    "created_at": string,"deleted_at": string | null,"event_id": string,"id": string,"is_active": boolean,"mode": Database["public"]['Enums']["usher_mode"],"name": string,"pin_hash": string,"pin_selector": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deleted_at"?: string | null,"event_id": string,"id"?: string,"is_active"?: boolean,"mode"?: Database["public"]['Enums']["usher_mode"],"name": string,"pin_hash": string,"pin_selector": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"deleted_at"?: string | null,"event_id"?: string,"id"?: string,"is_active"?: boolean,"mode"?: Database["public"]['Enums']["usher_mode"],"name"?: string,"pin_hash"?: string,"pin_selector"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ushers_event_id_fkey"
      columns: ["event_id"]
isOneToOne: false
      referencedRelation: "events"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "admin_apply_special_numbers":
{ Args: { "p_category": Database["public"]['Enums']["guest_category"],"p_event_id": string,"p_expected_hash": string,"p_order": string,"p_overwrite": boolean }; Returns: number
                           },
"admin_archive_event":
{ Args: { "p_event_id": string }; Returns: undefined
                           },
"admin_check_special_numbers":
{ Args: { "p_event_id": string,"p_numbers": (string)[] }; Returns: {
              "guest_name": string,"special_number": string
            }[]
                           },
"admin_clear_special_numbers":
{ Args: { "p_event_id": string,"p_guest_ids": (string)[] }; Returns: number
                           },
"admin_create_event":
{ Args: { "p_couple_names"?: string,"p_event_date": string,"p_name": string,"p_timezone"?: string,"p_venue"?: string }; Returns: string
                           },
"admin_create_login_qr":
{ Args: { "p_usher_id": string }; Returns: Json
                           },
"admin_create_usher":
{ Args: { "p_event_id": string,"p_mode"?: Database["public"]['Enums']["usher_mode"],"p_name": string }; Returns: Json
                           },
"admin_delete_usher":
{ Args: { "p_usher_id": string }; Returns: Json
                           },
"admin_import_guests":
{ Args: { "p_event_id": string,"p_rows": Json }; Returns: Json
                           },
"admin_manual_check_in":
{ Args: { "p_actual_pax": number,"p_guest_id": string }; Returns: Json
                           },
"admin_preview_special_numbers":
{ Args: { "p_category": Database["public"]['Enums']["guest_category"],"p_event_id": string,"p_order": string,"p_overwrite"?: boolean }; Returns: Json
                           },
"admin_reset_usher_pin":
{ Args: { "p_usher_id": string }; Returns: Json
                           },
"admin_revoke_device":
{ Args: { "p_device_id": string,"p_mode": Database["public"]['Enums']["revoke_mode"],"p_reason"?: string }; Returns: Json
                           },
"admin_update_check_in":
{ Args: { "p_check_in_id": string,"p_patch": Json,"p_reason"?: string }; Returns: Json
                           },
"admin_update_event":
{ Args: { "p_event_id": string,"p_patch": Json }; Returns: undefined
                           },
"admin_update_usher":
{ Args: { "p_patch": Json,"p_usher_id": string }; Returns: Json
                           },
"get_alerts":
{ Args: { "p_event_id": string }; Returns: Json
                           },
"pull_snapshot":
{ Args: { "p_client_now"?: string,"p_cursor"?: string,"p_limit"?: number }; Returns: Json
                           },
"push_outbox":
{ Args: { "p_client_now"?: string,"p_items": Json }; Returns: Json
                           },
"svc_abort_device":
{ Args: { "p_device_id": string }; Returns: undefined
                           },
"svc_attach_device_user":
{ Args: { "p_auth_user_id": string,"p_device_id": string }; Returns: undefined
                           },
"svc_devices_due_for_cleanup":
{ Args: { "p_limit"?: number }; Returns: {
              "auth_user_id": string,"device_id": string
            }[]
                           },
"svc_mark_auth_user_deleted":
{ Args: { "p_device_id": string }; Returns: undefined
                           },
"svc_terminated_device_user":
{ Args: { "p_device_id": string }; Returns: string
                           },
"svc_usher_login":
{ Args: { "p_app_version"?: string,"p_device_name"?: string,"p_event_code"?: string,"p_ip": string,"p_method": Database["public"]['Enums']["login_method"],"p_secret"?: string,"p_selector"?: string,"p_token"?: string }; Returns: Json
                           }
          }
          Enums: {
            "attendance_status": "not_arrived"|"checked_in"|"checked_out","auth_attempt_kind": "usher_login"|"invitation_url"|"screen_token","check_in_source": "device"|"admin"|"outbox_upload","check_in_status": "accepted"|"repeat"|"duplicate"|"conflict"|"quarantined","guest_category": "regular"|"vip"|"vvip","login_method": "pin"|"qr","quarantine_reason": "device_revoked"|"session_expired","revoke_mode": "quarantine"|"terminate","rsvp_status": "going"|"not_going"|"unconfirmed","usher_mode": "check_in"|"check_out"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "attendance_status": ["not_arrived", "checked_in", "checked_out"],"auth_attempt_kind": ["usher_login", "invitation_url", "screen_token"],"check_in_source": ["device", "admin", "outbox_upload"],"check_in_status": ["accepted", "repeat", "duplicate", "conflict", "quarantined"],"guest_category": ["regular", "vip", "vvip"],"login_method": ["pin", "qr"],"quarantine_reason": ["device_revoked", "session_expired"],"revoke_mode": ["quarantine", "terminate"],"rsvp_status": ["going", "not_going", "unconfirmed"],"usher_mode": ["check_in", "check_out"]
          }
        }
} as const
