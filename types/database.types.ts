
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "list_members": {
                  Row: {
                    "created_at": string,"invited_by": string | null,"list_id": string,"role": Database["public"]['Enums']["list_role"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"invited_by"?: string | null,"list_id": string,"role"?: Database["public"]['Enums']["list_role"],"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"invited_by"?: string | null,"list_id"?: string,"role"?: Database["public"]['Enums']["list_role"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "list_members_list_id_fkey"
      columns: ["list_id"]
isOneToOne: false
      referencedRelation: "lists"
      referencedColumns: ["id"]
    }
                  ]
                },"lists": {
                  Row: {
                    "archived_at": string | null,"created_at": string,"description": string | null,"id": string,"name": string,"owner_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"created_at"?: string,"description"?: string | null,"id"?: string,"name": string,"owner_id"?: string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"created_at"?: string,"description"?: string | null,"id"?: string,"name"?: string,"owner_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"profiles": {
                  Row: {
                    "avatar_url": string | null,"created_at": string,"display_name": string | null,"id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name"?: string | null,"id": string
                  }
                  Update: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name"?: string | null,"id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"task_status_events": {
                  Row: {
                    "changed_at": string,"changed_by": string | null,"from_behavior": Database["public"]['Enums']["status_behavior"] | null,"from_status_id": string | null,"id": number,"task_id": string,"to_behavior": Database["public"]['Enums']["status_behavior"],"to_status_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "changed_at"?: string,"changed_by"?: string | null,"from_behavior"?: Database["public"]['Enums']["status_behavior"] | null,"from_status_id"?: string | null,"id"?: never,"task_id": string,"to_behavior": Database["public"]['Enums']["status_behavior"],"to_status_id": string
                  }
                  Update: {
                    "changed_at"?: string,"changed_by"?: string | null,"from_behavior"?: Database["public"]['Enums']["status_behavior"] | null,"from_status_id"?: string | null,"id"?: never,"task_id"?: string,"to_behavior"?: Database["public"]['Enums']["status_behavior"],"to_status_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "task_status_events_from_status_id_fkey"
      columns: ["from_status_id"]
isOneToOne: false
      referencedRelation: "task_statuses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "task_status_events_task_id_fkey"
      columns: ["task_id"]
isOneToOne: false
      referencedRelation: "tasks"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "task_status_events_to_status_id_fkey"
      columns: ["to_status_id"]
isOneToOne: false
      referencedRelation: "task_statuses"
      referencedColumns: ["id"]
    }
                  ]
                },"task_statuses": {
                  Row: {
                    "archived_at": string | null,"behavior": Database["public"]['Enums']["status_behavior"],"created_at": string,"id": string,"label": string,"owner_id": string | null,"sort_order": number
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"behavior": Database["public"]['Enums']["status_behavior"],"created_at"?: string,"id"?: string,"label": string,"owner_id"?: string | null,"sort_order": number
                  }
                  Update: {
                    "archived_at"?: string | null,"behavior"?: Database["public"]['Enums']["status_behavior"],"created_at"?: string,"id"?: string,"label"?: string,"owner_id"?: string | null,"sort_order"?: number
                  }
                  Relationships: [
                    
                  ]
                },"tasks": {
                  Row: {
                    "assignee_id": string | null,"blocked_reason": string | null,"completed_at": string | null,"created_at": string,"created_by": string | null,"description": string | null,"due_at": string | null,"id": string,"list_id": string,"position": number,"priority": number | null,"status_changed_at": string,"status_id": string,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "assignee_id"?: string | null,"blocked_reason"?: string | null,"completed_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"due_at"?: string | null,"id"?: string,"list_id": string,"position"?: number,"priority"?: number | null,"status_changed_at"?: string,"status_id": string,"title": string,"updated_at"?: string
                  }
                  Update: {
                    "assignee_id"?: string | null,"blocked_reason"?: string | null,"completed_at"?: string | null,"created_at"?: string,"created_by"?: string | null,"description"?: string | null,"due_at"?: string | null,"id"?: string,"list_id"?: string,"position"?: number,"priority"?: number | null,"status_changed_at"?: string,"status_id"?: string,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "tasks_list_id_fkey"
      columns: ["list_id"]
isOneToOne: false
      referencedRelation: "lists"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tasks_status_id_fkey"
      columns: ["status_id"]
isOneToOne: false
      referencedRelation: "task_statuses"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "is_terminal":
{ Args: { "b": Database["public"]['Enums']["status_behavior"] }; Returns: boolean
                           },
"transfer_list_ownership":
{ Args: { "list_id": string,"new_owner": string }; Returns: undefined
                           }
          }
          Enums: {
            "list_role": "viewer"|"editor"|"owner","status_behavior": "backlog"|"todo"|"in_progress"|"blocked"|"in_review"|"completed"|"cancelled"
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
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "list_role": ["viewer", "editor", "owner"],"status_behavior": ["backlog", "todo", "in_progress", "blocked", "in_review", "completed", "cancelled"]
          }
        }
} as const
