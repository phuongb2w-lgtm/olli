export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      app_user: {
        Row: {
          auth_user_id: string | null
          created_at: string
          created_by: string | null
          display_name: string
          email: string
          id: string
          organization_id: string
          preferred_locale: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string
          created_by?: string | null
          display_name: string
          email: string
          id?: string
          organization_id: string
          preferred_locale?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string
          created_by?: string | null
          display_name?: string
          email?: string
          id?: string
          organization_id?: string
          preferred_locale?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "app_user_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "app_user_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "app_user_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      assessment: {
        Row: {
          assessed_on: string
          assessment_type_code: string
          class_id: string
          created_at: string
          created_by: string | null
          id: string
          max_score: number
          organization_id: string
          status: string
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assessed_on: string
          assessment_type_code: string
          class_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          max_score: number
          organization_id: string
          status?: string
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assessed_on?: string
          assessment_type_code?: string
          class_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          max_score?: number
          organization_id?: string
          status?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assessment_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "assessment_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "assessment_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      assessment_result: {
        Row: {
          assessment_id: string
          created_at: string
          enrollment_id: string
          finalized_at: string | null
          id: string
          max_score: number
          organization_id: string
          raw_score: number
          recorded_by: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assessment_id: string
          created_at?: string
          enrollment_id: string
          finalized_at?: string | null
          id?: string
          max_score: number
          organization_id: string
          raw_score: number
          recorded_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assessment_id?: string
          created_at?: string
          enrollment_id?: string
          finalized_at?: string | null
          id?: string
          max_score?: number
          organization_id?: string
          raw_score?: number
          recorded_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assessment_result_organization_id_assessment_id_fkey"
            columns: ["organization_id", "assessment_id"]
            isOneToOne: false
            referencedRelation: "assessment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "assessment_result_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "assessment_result_recorded_by_fk"
            columns: ["organization_id", "recorded_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "assessment_result_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      attendance: {
        Row: {
          created_at: string
          enrollment_id: string
          id: string
          organization_id: string
          recorded_at: string
          recorded_by: string | null
          status: string
          teaching_session_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          enrollment_id: string
          id?: string
          organization_id: string
          recorded_at?: string
          recorded_by?: string | null
          status: string
          teaching_session_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          enrollment_id?: string
          id?: string
          organization_id?: string
          recorded_at?: string
          recorded_by?: string | null
          status?: string
          teaching_session_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "attendance_organization_id_teaching_session_id_fkey"
            columns: ["organization_id", "teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "attendance_recorded_by_fk"
            columns: ["organization_id", "recorded_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "attendance_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      capital_asset: {
        Row: {
          category_code: string | null
          cost_group_id: string
          created_at: string
          created_by: string | null
          depreciation_method_code: string
          id: string
          is_quick_mode: boolean
          name: string
          notes: string | null
          organization_id: string
          original_cost: number
          placed_in_service_date: string
          retired_at: string | null
          status: string
          updated_at: string
          updated_by: string | null
          useful_life_months: number
        }
        Insert: {
          category_code?: string | null
          cost_group_id: string
          created_at?: string
          created_by?: string | null
          depreciation_method_code?: string
          id?: string
          is_quick_mode?: boolean
          name: string
          notes?: string | null
          organization_id: string
          original_cost: number
          placed_in_service_date: string
          retired_at?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          useful_life_months: number
        }
        Update: {
          category_code?: string | null
          cost_group_id?: string
          created_at?: string
          created_by?: string | null
          depreciation_method_code?: string
          id?: string
          is_quick_mode?: boolean
          name?: string
          notes?: string | null
          organization_id?: string
          original_cost?: number
          placed_in_service_date?: string
          retired_at?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          useful_life_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "capital_asset_organization_id_cost_group_id_fkey"
            columns: ["organization_id", "cost_group_id"]
            isOneToOne: false
            referencedRelation: "cost_group"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "capital_asset_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "capital_asset_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "capital_asset_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      charge: {
        Row: {
          amount: number
          charged_at: string
          created_at: string
          created_by: string | null
          currency_code: string
          description: string | null
          due_date: string | null
          enrollment_id: string | null
          guardian_id: string
          id: string
          organization_id: string
          status: string
          student_id: string
          tuition_plan_id: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          charged_at?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          due_date?: string | null
          enrollment_id?: string | null
          guardian_id: string
          id?: string
          organization_id: string
          status?: string
          student_id: string
          tuition_plan_id?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          charged_at?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          due_date?: string | null
          enrollment_id?: string | null
          guardian_id?: string
          id?: string
          organization_id?: string
          status?: string
          student_id?: string
          tuition_plan_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "charge_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "charge_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "charge_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "charge_organization_id_tuition_plan_id_fkey"
            columns: ["organization_id", "tuition_plan_id"]
            isOneToOne: false
            referencedRelation: "tuition_plan"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      class: {
        Row: {
          capacity: number | null
          course_id: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          organization_id: string
          status: string
          term_end_date: string | null
          term_start_date: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          capacity?: number | null
          course_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organization_id: string
          status?: string
          term_end_date?: string | null
          term_start_date?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          capacity?: number | null
          course_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organization_id?: string
          status?: string
          term_end_date?: string | null
          term_start_date?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "class_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_organization_id_course_id_fkey"
            columns: ["organization_id", "course_id"]
            isOneToOne: false
            referencedRelation: "course"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "class_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      class_schedule: {
        Row: {
          class_id: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          end_time: string
          id: string
          location: string | null
          organization_id: string
          room_id: string | null
          start_time: string
          status: string
          teacher_id: string | null
          updated_at: string
          updated_by: string | null
          weekday_code: string
        }
        Insert: {
          class_id: string
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          end_time: string
          id?: string
          location?: string | null
          organization_id: string
          room_id?: string | null
          start_time: string
          status?: string
          teacher_id?: string | null
          updated_at?: string
          updated_by?: string | null
          weekday_code: string
        }
        Update: {
          class_id?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          end_time?: string
          id?: string
          location?: string | null
          organization_id?: string
          room_id?: string | null
          start_time?: string
          status?: string
          teacher_id?: string | null
          updated_at?: string
          updated_by?: string | null
          weekday_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "class_schedule_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_schedule_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_schedule_room_fk"
            columns: ["organization_id", "room_id"]
            isOneToOne: false
            referencedRelation: "room"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_schedule_teacher_fk"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_schedule_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      class_teacher_assignment: {
        Row: {
          class_id: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          organization_id: string
          role_code: string
          status: string
          teacher_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          class_id: string
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          id?: string
          organization_id: string
          role_code?: string
          status?: string
          teacher_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          class_id?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id?: string
          role_code?: string
          status?: string
          teacher_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "class_teacher_assignment_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_teacher_assignment_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_teacher_assignment_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_teacher_assignment_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      cost_group: {
        Row: {
          code: string | null
          cost_domain_code: string
          created_at: string
          group_slot: number
          id: string
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code?: string | null
          cost_domain_code: string
          created_at?: string
          group_slot: number
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string | null
          cost_domain_code?: string
          created_at?: string
          group_slot?: number
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cost_group_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      course: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          level_code: string | null
          name: string
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          level_code?: string | null
          name: string
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          level_code?: string | null
          name?: string
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "course_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "course_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      depreciation_entry: {
        Row: {
          amount: number
          capital_asset_id: string
          created_at: string
          id: string
          organization_id: string
          period_month: string
          period_number: number
          posted_at: string | null
          status: string
        }
        Insert: {
          amount: number
          capital_asset_id: string
          created_at?: string
          id?: string
          organization_id: string
          period_month: string
          period_number: number
          posted_at?: string | null
          status?: string
        }
        Update: {
          amount?: number
          capital_asset_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          period_month?: string
          period_number?: number
          posted_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "depreciation_entry_organization_id_capital_asset_id_fkey"
            columns: ["organization_id", "capital_asset_id"]
            isOneToOne: false
            referencedRelation: "capital_asset"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      enrollment: {
        Row: {
          class_id: string
          created_at: string
          created_by: string | null
          end_date: string | null
          id: string
          organization_id: string
          start_date: string
          status: string
          student_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          class_id: string
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          id?: string
          organization_id: string
          start_date: string
          status?: string
          student_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          class_id?: string
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          id?: string
          organization_id?: string
          start_date?: string
          status?: string
          student_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "enrollment_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      expense: {
        Row: {
          amount: number
          class_id: string | null
          cost_group_id: string
          created_at: string
          created_by: string | null
          currency_code: string
          description: string | null
          expense_category_id: string
          id: string
          incurred_date: string
          organization_id: string
          reference: string | null
          status: string
          teacher_id: string | null
        }
        Insert: {
          amount: number
          class_id?: string | null
          cost_group_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          expense_category_id: string
          id?: string
          incurred_date: string
          organization_id: string
          reference?: string | null
          status?: string
          teacher_id?: string | null
        }
        Update: {
          amount?: number
          class_id?: string | null
          cost_group_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          expense_category_id?: string
          id?: string
          incurred_date?: string
          organization_id?: string
          reference?: string | null
          status?: string
          teacher_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expense_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "expense_organization_id_cost_group_id_fkey"
            columns: ["organization_id", "cost_group_id"]
            isOneToOne: false
            referencedRelation: "cost_group"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "expense_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "expense_organization_id_expense_category_id_fkey"
            columns: ["organization_id", "expense_category_id"]
            isOneToOne: false
            referencedRelation: "expense_category"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "expense_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      expense_category: {
        Row: {
          code: string | null
          cost_group_id: string
          created_at: string
          display_name: string
          id: string
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code?: string | null
          cost_group_id: string
          created_at?: string
          display_name: string
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string | null
          cost_group_id?: string
          created_at?: string
          display_name?: string
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_category_organization_id_cost_group_id_fkey"
            columns: ["organization_id", "cost_group_id"]
            isOneToOne: false
            referencedRelation: "cost_group"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      financial_adjustment: {
        Row: {
          adjusted_at: string
          adjustment_type_code: string
          amount_delta: number
          approved_by: string | null
          charge_id: string
          created_at: string
          id: string
          notes: string | null
          organization_id: string
          reason_code: string | null
          status: string
        }
        Insert: {
          adjusted_at?: string
          adjustment_type_code: string
          amount_delta: number
          approved_by?: string | null
          charge_id: string
          created_at?: string
          id?: string
          notes?: string | null
          organization_id: string
          reason_code?: string | null
          status?: string
        }
        Update: {
          adjusted_at?: string
          adjustment_type_code?: string
          amount_delta?: number
          approved_by?: string | null
          charge_id?: string
          created_at?: string
          id?: string
          notes?: string | null
          organization_id?: string
          reason_code?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "financial_adjustment_organization_id_approved_by_fkey"
            columns: ["organization_id", "approved_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "financial_adjustment_organization_id_charge_id_fkey"
            columns: ["organization_id", "charge_id"]
            isOneToOne: false
            referencedRelation: "charge"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "financial_adjustment_organization_id_charge_id_fkey"
            columns: ["organization_id", "charge_id"]
            isOneToOne: false
            referencedRelation: "charge_balance"
            referencedColumns: ["organization_id", "charge_id"]
          },
        ]
      }
      guardian: {
        Row: {
          created_at: string
          created_by: string | null
          email: string | null
          family_name: string
          given_name: string
          id: string
          organization_id: string
          phone: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          email?: string | null
          family_name: string
          given_name: string
          id?: string
          organization_id: string
          phone?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          email?: string | null
          family_name?: string
          given_name?: string
          id?: string
          organization_id?: string
          phone?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "guardian_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "guardian_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "guardian_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      observation_indicator: {
        Row: {
          code: string
          created_at: string
          id: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      observation_rating: {
        Row: {
          created_at: string
          id: string
          indicator_code: string
          organization_id: string
          rating_code: string
          teacher_observation_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          indicator_code: string
          organization_id: string
          rating_code: string
          teacher_observation_id: string
        }
        Update: {
          created_at?: string
          id?: string
          indicator_code?: string
          organization_id?: string
          rating_code?: string
          teacher_observation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "observation_rating_indicator_code_fkey"
            columns: ["indicator_code"]
            isOneToOne: false
            referencedRelation: "observation_indicator"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "observation_rating_organization_id_teacher_observation_id_fkey"
            columns: ["organization_id", "teacher_observation_id"]
            isOneToOne: false
            referencedRelation: "teacher_observation"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      organization: {
        Row: {
          created_at: string
          currency_code: string
          default_locale: string
          id: string
          name: string
          status: string
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          currency_code?: string
          default_locale?: string
          id?: string
          name: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          currency_code?: string
          default_locale?: string
          id?: string
          name?: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      payment: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          currency_code: string
          guardian_id: string
          id: string
          method_code: string
          organization_id: string
          paid_at: string
          reference_number: string | null
          status: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          currency_code?: string
          guardian_id: string
          id?: string
          method_code?: string
          organization_id: string
          paid_at?: string
          reference_number?: string | null
          status?: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          currency_code?: string
          guardian_id?: string
          id?: string
          method_code?: string
          organization_id?: string
          paid_at?: string
          reference_number?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      payment_allocation: {
        Row: {
          allocated_at: string
          amount: number
          charge_id: string
          id: string
          organization_id: string
          payment_id: string
        }
        Insert: {
          allocated_at?: string
          amount: number
          charge_id: string
          id?: string
          organization_id: string
          payment_id: string
        }
        Update: {
          allocated_at?: string
          amount?: number
          charge_id?: string
          id?: string
          organization_id?: string
          payment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_allocation_organization_id_charge_id_fkey"
            columns: ["organization_id", "charge_id"]
            isOneToOne: false
            referencedRelation: "charge"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_allocation_organization_id_charge_id_fkey"
            columns: ["organization_id", "charge_id"]
            isOneToOne: false
            referencedRelation: "charge_balance"
            referencedColumns: ["organization_id", "charge_id"]
          },
          {
            foreignKeyName: "payment_allocation_organization_id_payment_id_fkey"
            columns: ["organization_id", "payment_id"]
            isOneToOne: false
            referencedRelation: "payment"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      permission: {
        Row: {
          code: string
          created_at: string
          id: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      progress_evaluation: {
        Row: {
          class_id: string
          created_at: string
          enrollment_id: string
          evaluated_at: string
          evaluation_period_end: string
          evaluation_period_start: string
          id: string
          improvement_code: string
          organization_id: string
          progress_level_code: string
          status: string
          summary_comment: string | null
          teacher_id: string
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          enrollment_id: string
          evaluated_at: string
          evaluation_period_end: string
          evaluation_period_start: string
          id?: string
          improvement_code: string
          organization_id: string
          progress_level_code: string
          status?: string
          summary_comment?: string | null
          teacher_id: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          enrollment_id?: string
          evaluated_at?: string
          evaluation_period_end?: string
          evaluation_period_start?: string
          id?: string
          improvement_code?: string
          organization_id?: string
          progress_level_code?: string
          status?: string
          summary_comment?: string | null
          teacher_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "progress_evaluation_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "progress_evaluation_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "progress_evaluation_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      role: {
        Row: {
          code: string
          created_at: string
          id: string
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permission: {
        Row: {
          permission_id: string
          role_id: string
        }
        Insert: {
          permission_id: string
          role_id: string
        }
        Update: {
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permission_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permission"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permission_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "role"
            referencedColumns: ["id"]
          },
        ]
      }
      room: {
        Row: {
          capacity: number | null
          code: string | null
          created_at: string
          created_by: string | null
          id: string
          name: string
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          capacity?: number | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          capacity?: number | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "room_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "room_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "room_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      student: {
        Row: {
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          family_name: string
          given_name: string
          id: string
          organization_id: string
          status: string
          student_code: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          family_name: string
          given_name: string
          id?: string
          organization_id: string
          status?: string
          student_code?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          family_name?: string
          given_name?: string
          id?: string
          organization_id?: string
          status?: string
          student_code?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "student_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "student_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      student_guardian: {
        Row: {
          created_at: string
          created_by: string | null
          guardian_id: string
          id: string
          is_billing_contact: boolean
          is_primary_contact: boolean
          organization_id: string
          relationship_type: string
          status: string
          student_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          guardian_id: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          organization_id: string
          relationship_type?: string
          status?: string
          student_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          guardian_id?: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          organization_id?: string
          relationship_type?: string
          status?: string
          student_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "student_guardian_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "student_guardian_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "student_guardian_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "student_guardian_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      teacher: {
        Row: {
          created_at: string
          created_by: string | null
          employee_code: string | null
          family_name: string
          given_name: string
          id: string
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          employee_code?: string | null
          family_name: string
          given_name: string
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          employee_code?: string | null
          family_name?: string
          given_name?: string
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "teacher_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teacher_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["id"]
          },
        ]
      }
      teacher_observation: {
        Row: {
          class_id: string
          comment: string | null
          created_at: string
          created_by: string | null
          enrollment_id: string
          id: string
          observed_at: string
          organization_id: string
          status: string
          teacher_id: string
          teaching_session_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          class_id: string
          comment?: string | null
          created_at?: string
          created_by?: string | null
          enrollment_id: string
          id?: string
          observed_at: string
          organization_id: string
          status?: string
          teacher_id: string
          teaching_session_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          class_id?: string
          comment?: string | null
          created_at?: string
          created_by?: string | null
          enrollment_id?: string
          id?: string
          observed_at?: string
          organization_id?: string
          status?: string
          teacher_id?: string
          teaching_session_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "teacher_observation_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_observation_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_observation_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_observation_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_observation_teaching_session_id_fkey"
            columns: ["teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teacher_observation_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      teaching_session: {
        Row: {
          actual_end_at: string | null
          actual_start_at: string | null
          class_id: string
          class_schedule_id: string | null
          created_at: string
          created_by: string | null
          id: string
          occurrence_date: string | null
          organization_id: string
          room_id: string | null
          scheduled_end_at: string
          scheduled_start_at: string
          status: string
          teacher_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          actual_end_at?: string | null
          actual_start_at?: string | null
          class_id: string
          class_schedule_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          occurrence_date?: string | null
          organization_id: string
          room_id?: string | null
          scheduled_end_at: string
          scheduled_start_at: string
          status?: string
          teacher_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          actual_end_at?: string | null
          actual_start_at?: string | null
          class_id?: string
          class_schedule_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          occurrence_date?: string | null
          organization_id?: string
          room_id?: string | null
          scheduled_end_at?: string
          scheduled_start_at?: string
          status?: string
          teacher_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "teaching_session_class_schedule_id_fkey"
            columns: ["class_schedule_id"]
            isOneToOne: false
            referencedRelation: "class_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teaching_session_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teaching_session_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teaching_session_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teaching_session_room_fk"
            columns: ["organization_id", "room_id"]
            isOneToOne: false
            referencedRelation: "room"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teaching_session_updated_by_fk"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      tuition_plan: {
        Row: {
          amount: number
          billing_frequency_code: string
          class_id: string | null
          course_id: string | null
          created_at: string
          currency_code: string
          effective_from: string
          effective_to: string | null
          id: string
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          billing_frequency_code?: string
          class_id?: string | null
          course_id?: string | null
          created_at?: string
          currency_code?: string
          effective_from: string
          effective_to?: string | null
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          billing_frequency_code?: string
          class_id?: string | null
          course_id?: string | null
          created_at?: string
          currency_code?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tuition_plan_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "tuition_plan_organization_id_course_id_fkey"
            columns: ["organization_id", "course_id"]
            isOneToOne: false
            referencedRelation: "course"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "tuition_plan_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      user_role: {
        Row: {
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          organization_id: string
          role_id: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id: string
          role_id: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id?: string
          role_id?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_role_organization_id_role_id_fkey"
            columns: ["organization_id", "role_id"]
            isOneToOne: false
            referencedRelation: "role"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "user_role_organization_id_user_id_fkey"
            columns: ["organization_id", "user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
    }
    Views: {
      charge_balance: {
        Row: {
          charge_id: string | null
          organization_id: string | null
          outstanding_balance: number | null
        }
        Insert: {
          charge_id?: string | null
          organization_id?: string | null
          outstanding_balance?: never
        }
        Update: {
          charge_id?: string | null
          organization_id?: string | null
          outstanding_balance?: never
        }
        Relationships: []
      }
    }
    Functions: {
      _cb_as_anon: { Args: never; Returns: undefined }
      _cb_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _cb_as_super: { Args: never; Returns: undefined }
      _cb_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _loc_as_anon: { Args: never; Returns: undefined }
      _loc_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _loc_as_super: { Args: never; Returns: undefined }
      _loc_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _sec_as_anon: { Args: never; Returns: undefined }
      _sec_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _sec_as_super: { Args: never; Returns: undefined }
      _sec_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      capital_asset_period_month: {
        Args: { p_period_number: number; p_placed_in_service: string }
        Returns: string
      }
      create_capital_asset: {
        Args: {
          p_category_code?: string
          p_is_quick_mode?: boolean
          p_name: string
          p_notes?: string
          p_original_cost: number
          p_placed_in_service_date: string
          p_useful_life_months: number
        }
        Returns: string
      }
      create_quick_capital_asset: {
        Args: {
          p_name?: string
          p_placed_in_service_date: string
          p_total_investment: number
          p_useful_life_months: number
        }
        Returns: string
      }
      current_app_user_id: { Args: never; Returns: string }
      current_organization_id: { Args: never; Returns: string }
      generate_depreciation_schedule: {
        Args: { p_capital_asset_id: string }
        Returns: undefined
      }
      generate_teaching_sessions: {
        Args: {
          p_class_schedule_id: string
          p_range_end: string
          p_range_start: string
        }
        Returns: number
      }
      has_permission: { Args: { p_code: string }; Returns: boolean }
      is_active_app_user: { Args: never; Returns: boolean }
      post_depreciation_through: {
        Args: { p_capital_asset_id: string; p_through_month: string }
        Returns: number
      }
      resolve_capital_cost_group_id: {
        Args: { p_organization_id: string }
        Returns: string
      }
      retire_capital_asset: {
        Args: { p_capital_asset_id: string; p_retired_at?: string }
        Returns: undefined
      }
      seed_organization_cost_categories: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      set_own_preferred_locale: {
        Args: { p_locale: string }
        Returns: undefined
      }
      straight_line_depreciation_amount: {
        Args: {
          p_original_cost: number
          p_period_number: number
          p_useful_life_months: number
        }
        Returns: number
      }
      transfer_enrollment: {
        Args: {
          p_destination_class_id: string
          p_destination_start_date: string
          p_destination_status: string
          p_source_enrollment_id: string
        }
        Returns: string
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

