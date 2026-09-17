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
          agreed_tuition_snapshot: number | null
          amount: number
          charge_source_code: string | null
          charged_at: string
          created_at: string
          created_by: string | null
          currency_code: string
          description: string | null
          due_date: string | null
          enrollment_financial_terms_id: string | null
          enrollment_id: string | null
          enrollment_payment_schedule_item_id: string | null
          guardian_id: string
          id: string
          net_tuition_snapshot: number | null
          organization_id: string
          status: string
          student_id: string
          tuition_plan_id: string | null
          updated_at: string
        }
        Insert: {
          agreed_tuition_snapshot?: number | null
          amount: number
          charge_source_code?: string | null
          charged_at?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          due_date?: string | null
          enrollment_financial_terms_id?: string | null
          enrollment_id?: string | null
          enrollment_payment_schedule_item_id?: string | null
          guardian_id: string
          id?: string
          net_tuition_snapshot?: number | null
          organization_id: string
          status?: string
          student_id: string
          tuition_plan_id?: string | null
          updated_at?: string
        }
        Update: {
          agreed_tuition_snapshot?: number | null
          amount?: number
          charge_source_code?: string | null
          charged_at?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          due_date?: string | null
          enrollment_financial_terms_id?: string | null
          enrollment_id?: string | null
          enrollment_payment_schedule_item_id?: string | null
          guardian_id?: string
          id?: string
          net_tuition_snapshot?: number | null
          organization_id?: string
          status?: string
          student_id?: string
          tuition_plan_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "charge_enrollment_financial_terms_fk"
            columns: ["organization_id", "enrollment_financial_terms_id"]
            isOneToOne: false
            referencedRelation: "enrollment_financial_terms"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "charge_enrollment_payment_schedule_item_fk"
            columns: ["organization_id", "enrollment_payment_schedule_item_id"]
            isOneToOne: false
            referencedRelation: "enrollment_payment_schedule_item"
            referencedColumns: ["organization_id", "id"]
          },
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
      class_cost_allocation: {
        Row: {
          accounting_period: string
          allocated_amount: number
          allocation_basis_code: string
          allocation_batch_id: string
          class_id: string
          cost_allocation_rule_id: string
          cost_domain_code: string
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          sequence_number: number
          source_amount_snapshot: number
          source_record_id: string
          source_scope_code: string
          source_type: string
          status: string
          weight_total: number
          weight_value: number
        }
        Insert: {
          accounting_period: string
          allocated_amount: number
          allocation_basis_code: string
          allocation_batch_id: string
          class_id: string
          cost_allocation_rule_id: string
          cost_domain_code: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id: string
          sequence_number: number
          source_amount_snapshot: number
          source_record_id: string
          source_scope_code: string
          source_type: string
          status?: string
          weight_total?: number
          weight_value?: number
        }
        Update: {
          accounting_period?: string
          allocated_amount?: number
          allocation_basis_code?: string
          allocation_batch_id?: string
          class_id?: string
          cost_allocation_rule_id?: string
          cost_domain_code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id?: string
          sequence_number?: number
          source_amount_snapshot?: number
          source_record_id?: string
          source_scope_code?: string
          source_type?: string
          status?: string
          weight_total?: number
          weight_value?: number
        }
        Relationships: [
          {
            foreignKeyName: "class_cost_allocation_organization_id_allocation_batch_id_fkey"
            columns: ["organization_id", "allocation_batch_id"]
            isOneToOne: false
            referencedRelation: "class_cost_allocation_batch"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_cost_allocation_rule_fkey"
            columns: ["organization_id", "cost_allocation_rule_id"]
            isOneToOne: false
            referencedRelation: "cost_allocation_rule"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      class_cost_allocation_batch: {
        Row: {
          accounting_period: string
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          status: string
          void_notes: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          accounting_period: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id: string
          status?: string
          void_notes?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          accounting_period?: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id?: string
          status?: string
          void_notes?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "class_cost_allocation_batch_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_batch_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "class_cost_allocation_batch_organization_id_voided_by_fkey"
            columns: ["organization_id", "voided_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      class_financial_scenario: {
        Row: {
          assumed_net_tuition_per_learner: number
          capacity_snapshot: number | null
          class_id: string | null
          created_at: string
          created_by: string | null
          economics_snapshot: Json | null
          finalized_at: string | null
          finalized_by: string | null
          id: string
          marketing_assumption_basis: string
          marketing_sales_assumption: number
          monthly_depreciation_assumption: number
          monthly_operating_overhead_assumption: number
          monthly_shared_personnel_assumption: number
          organization_id: string
          per_session_rate_snapshot: number | null
          per_session_teacher_rate: number | null
          planned_learner_count: number
          planned_months: number
          planned_session_count: number
          scenario_name: string
          staff_compensation_rule_id: string | null
          status: string
          tuition_assumption_mode: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assumed_net_tuition_per_learner?: number
          capacity_snapshot?: number | null
          class_id?: string | null
          created_at?: string
          created_by?: string | null
          economics_snapshot?: Json | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          marketing_assumption_basis?: string
          marketing_sales_assumption?: number
          monthly_depreciation_assumption?: number
          monthly_operating_overhead_assumption?: number
          monthly_shared_personnel_assumption?: number
          organization_id: string
          per_session_rate_snapshot?: number | null
          per_session_teacher_rate?: number | null
          planned_learner_count: number
          planned_months: number
          planned_session_count: number
          scenario_name: string
          staff_compensation_rule_id?: string | null
          status?: string
          tuition_assumption_mode?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assumed_net_tuition_per_learner?: number
          capacity_snapshot?: number | null
          class_id?: string | null
          created_at?: string
          created_by?: string | null
          economics_snapshot?: Json | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          marketing_assumption_basis?: string
          marketing_sales_assumption?: number
          monthly_depreciation_assumption?: number
          monthly_operating_overhead_assumption?: number
          monthly_shared_personnel_assumption?: number
          organization_id?: string
          per_session_rate_snapshot?: number | null
          per_session_teacher_rate?: number | null
          planned_learner_count?: number
          planned_months?: number
          planned_session_count?: number
          scenario_name?: string
          staff_compensation_rule_id?: string | null
          status?: string
          tuition_assumption_mode?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "class_financial_scenario_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_financial_scenario_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_financial_scenario_organization_id_finalized_by_fkey"
            columns: ["organization_id", "finalized_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_financial_scenario_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "class_financial_scenario_organization_id_staff_compensatio_fkey"
            columns: ["organization_id", "staff_compensation_rule_id"]
            isOneToOne: false
            referencedRelation: "staff_compensation_rule"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_financial_scenario_organization_id_updated_by_fkey"
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
      cost_allocation_rule: {
        Row: {
          allocation_basis_code: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          notes: string | null
          organization_id: string
          source_scope_code: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allocation_basis_code: string
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          id?: string
          notes?: string | null
          organization_id: string
          source_scope_code: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allocation_basis_code?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          notes?: string | null
          organization_id?: string
          source_scope_code?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cost_allocation_rule_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "cost_allocation_rule_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_allocation_rule_organization_id_updated_by_fkey"
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
      enrollment_financial_terms: {
        Row: {
          agreed_tuition_amount: number
          agreement_date: string
          charges_generated_at: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          discount_amount: number
          enrollment_id: string
          id: string
          net_tuition_amount: number
          notes: string | null
          organization_id: string
          payment_plan_mode: string | null
          recognition_basis_code: string | null
          status: string
          superseded_by_id: string | null
          tuition_plan_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          agreed_tuition_amount: number
          agreement_date?: string
          charges_generated_at?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          discount_amount?: number
          enrollment_id: string
          id?: string
          net_tuition_amount: number
          notes?: string | null
          organization_id: string
          payment_plan_mode?: string | null
          recognition_basis_code?: string | null
          status?: string
          superseded_by_id?: string | null
          tuition_plan_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          agreed_tuition_amount?: number
          agreement_date?: string
          charges_generated_at?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          discount_amount?: number
          enrollment_id?: string
          id?: string
          net_tuition_amount?: number
          notes?: string | null
          organization_id?: string
          payment_plan_mode?: string | null
          recognition_basis_code?: string | null
          status?: string
          superseded_by_id?: string | null
          tuition_plan_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_superseded_by_i_fkey"
            columns: ["organization_id", "superseded_by_id"]
            isOneToOne: false
            referencedRelation: "enrollment_financial_terms"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_tuition_plan_id_fkey"
            columns: ["organization_id", "tuition_plan_id"]
            isOneToOne: false
            referencedRelation: "tuition_plan"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_financial_terms_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      enrollment_payment_schedule_item: {
        Row: {
          amount: number
          created_at: string
          due_date: string
          enrollment_financial_terms_id: string
          id: string
          label: string | null
          organization_id: string
          sequence_number: number
          status: string
        }
        Insert: {
          amount: number
          created_at?: string
          due_date: string
          enrollment_financial_terms_id: string
          id?: string
          label?: string | null
          organization_id: string
          sequence_number: number
          status?: string
        }
        Update: {
          amount?: number
          created_at?: string
          due_date?: string
          enrollment_financial_terms_id?: string
          id?: string
          label?: string | null
          organization_id?: string
          sequence_number?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "enrollment_payment_schedule_i_organization_id_enrollment_f_fkey"
            columns: ["organization_id", "enrollment_financial_terms_id"]
            isOneToOne: false
            referencedRelation: "enrollment_financial_terms"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      enrollment_recognition_config: {
        Row: {
          created_at: string
          created_by: string | null
          enrollment_financial_terms_id: string
          enrollment_id: string
          id: string
          net_tuition_snapshot: number
          organization_id: string
          recognition_basis_code: string
          recognition_unit_count: number | null
          status: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          enrollment_financial_terms_id: string
          enrollment_id: string
          id?: string
          net_tuition_snapshot: number
          organization_id: string
          recognition_basis_code: string
          recognition_unit_count?: number | null
          status?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          enrollment_financial_terms_id?: string
          enrollment_id?: string
          id?: string
          net_tuition_snapshot?: number
          organization_id?: string
          recognition_basis_code?: string
          recognition_unit_count?: number | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "enrollment_recognition_config_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_recognition_config_organization_id_enrollment_f_fkey"
            columns: ["organization_id", "enrollment_financial_terms_id"]
            isOneToOne: false
            referencedRelation: "enrollment_financial_terms"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_recognition_config_organization_id_enrollment_i_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_recognition_config_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      enrollment_recognition_stage: {
        Row: {
          amount: number
          assessment_id: string | null
          created_at: string
          enrollment_recognition_config_id: string
          id: string
          label: string | null
          organization_id: string
          sequence_number: number
          status: string
        }
        Insert: {
          amount: number
          assessment_id?: string | null
          created_at?: string
          enrollment_recognition_config_id: string
          id?: string
          label?: string | null
          organization_id: string
          sequence_number: number
          status?: string
        }
        Update: {
          amount?: number
          assessment_id?: string | null
          created_at?: string
          enrollment_recognition_config_id?: string
          id?: string
          label?: string | null
          organization_id?: string
          sequence_number?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "enrollment_recognition_stage_organization_id_assessment_id_fkey"
            columns: ["organization_id", "assessment_id"]
            isOneToOne: false
            referencedRelation: "assessment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "enrollment_recognition_stage_organization_id_enrollment_re_fkey"
            columns: ["organization_id", "enrollment_recognition_config_id"]
            isOneToOne: false
            referencedRelation: "enrollment_recognition_config"
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
      lead: {
        Row: {
          assigned_user_id: string | null
          converted_at: string | null
          created_at: string
          created_by: string | null
          id: string
          lead_campaign_id: string | null
          lead_source_id: string | null
          lost_at: string | null
          lost_by: string | null
          lost_notes: string | null
          lost_reason_id: string | null
          notes_summary: string | null
          organization_id: string
          referral_guardian_id: string | null
          referral_student_id: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          assigned_user_id?: string | null
          converted_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          lead_campaign_id?: string | null
          lead_source_id?: string | null
          lost_at?: string | null
          lost_by?: string | null
          lost_notes?: string | null
          lost_reason_id?: string | null
          notes_summary?: string | null
          organization_id: string
          referral_guardian_id?: string | null
          referral_student_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          assigned_user_id?: string | null
          converted_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          lead_campaign_id?: string | null
          lead_source_id?: string | null
          lost_at?: string | null
          lost_by?: string | null
          lost_notes?: string | null
          lost_reason_id?: string | null
          notes_summary?: string | null
          organization_id?: string
          referral_guardian_id?: string | null
          referral_student_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_organization_id_assigned_user_id_fkey"
            columns: ["organization_id", "assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_organization_id_lead_campaign_id_fkey"
            columns: ["organization_id", "lead_campaign_id"]
            isOneToOne: false
            referencedRelation: "lead_campaign"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_lead_source_id_fkey"
            columns: ["organization_id", "lead_source_id"]
            isOneToOne: false
            referencedRelation: "lead_source"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_lost_by_fkey"
            columns: ["organization_id", "lost_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_lost_reason_id_fkey"
            columns: ["organization_id", "lost_reason_id"]
            isOneToOne: false
            referencedRelation: "lead_lost_reason"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_referral_guardian_id_fkey"
            columns: ["organization_id", "referral_guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_referral_student_id_fkey"
            columns: ["organization_id", "referral_student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_activity: {
        Row: {
          activity_type_code: string
          content: string | null
          created_at: string
          created_by: string
          id: string
          lead_id: string
          metadata: Json
          occurred_at: string
          organization_id: string
        }
        Insert: {
          activity_type_code: string
          content?: string | null
          created_at?: string
          created_by: string
          id?: string
          lead_id: string
          metadata?: Json
          occurred_at?: string
          organization_id: string
        }
        Update: {
          activity_type_code?: string
          content?: string | null
          created_at?: string
          created_by?: string
          id?: string
          lead_id?: string
          metadata?: Json
          occurred_at?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_activity_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_activity_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_assignment: {
        Row: {
          changed_at: string
          changed_by: string
          id: string
          lead_id: string
          new_assigned_user_id: string | null
          note: string | null
          organization_id: string
          previous_assigned_user_id: string | null
        }
        Insert: {
          changed_at?: string
          changed_by: string
          id?: string
          lead_id: string
          new_assigned_user_id?: string | null
          note?: string | null
          organization_id: string
          previous_assigned_user_id?: string | null
        }
        Update: {
          changed_at?: string
          changed_by?: string
          id?: string
          lead_id?: string
          new_assigned_user_id?: string | null
          note?: string | null
          organization_id?: string
          previous_assigned_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_assignment_organization_id_changed_by_fkey"
            columns: ["organization_id", "changed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_assignment_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_assignment_organization_id_new_assigned_user_id_fkey"
            columns: ["organization_id", "new_assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_assignment_organization_id_previous_assigned_user_id_fkey"
            columns: ["organization_id", "previous_assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_campaign: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          end_date: string | null
          expense_id: string | null
          id: string
          lead_source_id: string | null
          name: string
          organization_id: string
          start_date: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          expense_id?: string | null
          id?: string
          lead_source_id?: string | null
          name: string
          organization_id: string
          start_date?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          expense_id?: string | null
          id?: string
          lead_source_id?: string | null
          name?: string
          organization_id?: string
          start_date?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_campaign_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_campaign_organization_id_expense_id_fkey"
            columns: ["organization_id", "expense_id"]
            isOneToOne: false
            referencedRelation: "expense"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_campaign_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_campaign_organization_id_lead_source_id_fkey"
            columns: ["organization_id", "lead_source_id"]
            isOneToOne: false
            referencedRelation: "lead_source"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_campaign_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_candidate: {
        Row: {
          converted_student_id: string | null
          created_at: string
          created_by: string | null
          date_of_birth: string | null
          family_name: string
          given_name: string
          id: string
          is_primary_candidate: boolean
          lead_id: string
          organization_id: string
          status: string
          target_class_id: string | null
          target_course_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          converted_student_id?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          family_name: string
          given_name: string
          id?: string
          is_primary_candidate?: boolean
          lead_id: string
          organization_id: string
          status?: string
          target_class_id?: string | null
          target_course_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          converted_student_id?: string | null
          created_at?: string
          created_by?: string | null
          date_of_birth?: string | null
          family_name?: string
          given_name?: string
          id?: string
          is_primary_candidate?: boolean
          lead_id?: string
          organization_id?: string
          status?: string
          target_class_id?: string | null
          target_course_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_candidate_converted_student_fk"
            columns: ["organization_id", "converted_student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_organization_id_target_class_id_fkey"
            columns: ["organization_id", "target_class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_organization_id_target_course_id_fkey"
            columns: ["organization_id", "target_course_id"]
            isOneToOne: false
            referencedRelation: "course"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_candidate_identity_resolution: {
        Row: {
          id: string
          identity_snapshot: Json
          is_stale: boolean
          lead_candidate_id: string
          organization_id: string
          resolution_mode: string
          resolved_at: string
          resolved_by: string
          strong_match_acknowledged: boolean
          student_id: string | null
          updated_at: string
        }
        Insert: {
          id?: string
          identity_snapshot?: Json
          is_stale?: boolean
          lead_candidate_id: string
          organization_id: string
          resolution_mode: string
          resolved_at?: string
          resolved_by: string
          strong_match_acknowledged?: boolean
          student_id?: string | null
          updated_at?: string
        }
        Update: {
          id?: string
          identity_snapshot?: Json
          is_stale?: boolean
          lead_candidate_id?: string
          organization_id?: string
          resolution_mode?: string
          resolved_at?: string
          resolved_by?: string
          strong_match_acknowledged?: boolean
          student_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_candidate_identity_resol_organization_id_lead_candida_fkey"
            columns: ["organization_id", "lead_candidate_id"]
            isOneToOne: true
            referencedRelation: "lead_candidate"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_identity_resolu_organization_id_resolved_by_fkey"
            columns: ["organization_id", "resolved_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_candidate_identity_resolut_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_contact: {
        Row: {
          converted_guardian_id: string | null
          created_at: string
          created_by: string | null
          email: string | null
          email_normalized: string | null
          family_name: string
          given_name: string
          id: string
          is_billing_contact: boolean
          is_primary_contact: boolean
          lead_id: string
          organization_id: string
          phone: string | null
          phone_normalized: string | null
          relationship_type: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          converted_guardian_id?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          email_normalized?: string | null
          family_name: string
          given_name: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          lead_id: string
          organization_id: string
          phone?: string | null
          phone_normalized?: string | null
          relationship_type?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          converted_guardian_id?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          email_normalized?: string | null
          family_name?: string
          given_name?: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          lead_id?: string
          organization_id?: string
          phone?: string | null
          phone_normalized?: string | null
          relationship_type?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_contact_converted_guardian_fk"
            columns: ["organization_id", "converted_guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_contact_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_contact_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_contact_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_contact_identity_resolution: {
        Row: {
          guardian_id: string | null
          id: string
          identity_snapshot: Json
          is_stale: boolean
          lead_contact_id: string
          organization_id: string
          resolution_mode: string
          resolved_at: string
          resolved_by: string
          strong_match_acknowledged: boolean
          updated_at: string
        }
        Insert: {
          guardian_id?: string | null
          id?: string
          identity_snapshot?: Json
          is_stale?: boolean
          lead_contact_id: string
          organization_id: string
          resolution_mode: string
          resolved_at?: string
          resolved_by: string
          strong_match_acknowledged?: boolean
          updated_at?: string
        }
        Update: {
          guardian_id?: string | null
          id?: string
          identity_snapshot?: Json
          is_stale?: boolean
          lead_contact_id?: string
          organization_id?: string
          resolution_mode?: string
          resolved_at?: string
          resolved_by?: string
          strong_match_acknowledged?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_contact_identity_resolut_organization_id_lead_contact_fkey"
            columns: ["organization_id", "lead_contact_id"]
            isOneToOne: true
            referencedRelation: "lead_contact"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_contact_identity_resoluti_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_contact_identity_resoluti_organization_id_resolved_by_fkey"
            columns: ["organization_id", "resolved_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_conversion: {
        Row: {
          assigned_user_id: string | null
          converted_at: string
          converted_by: string
          id: string
          lead_campaign_id: string | null
          lead_id: string
          lead_source_id: string | null
          metadata: Json
          organization_id: string
          referral_guardian_id: string | null
          referral_student_id: string | null
        }
        Insert: {
          assigned_user_id?: string | null
          converted_at?: string
          converted_by: string
          id?: string
          lead_campaign_id?: string | null
          lead_id: string
          lead_source_id?: string | null
          metadata?: Json
          organization_id: string
          referral_guardian_id?: string | null
          referral_student_id?: string | null
        }
        Update: {
          assigned_user_id?: string | null
          converted_at?: string
          converted_by?: string
          id?: string
          lead_campaign_id?: string | null
          lead_id?: string
          lead_source_id?: string | null
          metadata?: Json
          organization_id?: string
          referral_guardian_id?: string | null
          referral_student_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_conversion_organization_id_assigned_user_id_fkey"
            columns: ["organization_id", "assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_converted_by_fkey"
            columns: ["organization_id", "converted_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_lead_campaign_id_fkey"
            columns: ["organization_id", "lead_campaign_id"]
            isOneToOne: false
            referencedRelation: "lead_campaign"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: true
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_lead_source_id_fkey"
            columns: ["organization_id", "lead_source_id"]
            isOneToOne: false
            referencedRelation: "lead_source"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_referral_guardian_id_fkey"
            columns: ["organization_id", "referral_guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_organization_id_referral_student_id_fkey"
            columns: ["organization_id", "referral_student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_conversion_candidate: {
        Row: {
          id: string
          lead_candidate_id: string
          lead_conversion_id: string
          organization_id: string
          resolution_mode: string
          student_id: string
          was_created: boolean
        }
        Insert: {
          id?: string
          lead_candidate_id: string
          lead_conversion_id: string
          organization_id: string
          resolution_mode: string
          student_id: string
          was_created: boolean
        }
        Update: {
          id?: string
          lead_candidate_id?: string
          lead_conversion_id?: string
          organization_id?: string
          resolution_mode?: string
          student_id?: string
          was_created?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "lead_conversion_candidate_organization_id_lead_candidate_i_fkey"
            columns: ["organization_id", "lead_candidate_id"]
            isOneToOne: false
            referencedRelation: "lead_candidate"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_candidate_organization_id_lead_conversion__fkey"
            columns: ["organization_id", "lead_conversion_id"]
            isOneToOne: false
            referencedRelation: "lead_conversion"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_candidate_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_conversion_contact: {
        Row: {
          guardian_id: string
          id: string
          lead_contact_id: string
          lead_conversion_id: string
          organization_id: string
          resolution_mode: string
          was_created: boolean
        }
        Insert: {
          guardian_id: string
          id?: string
          lead_contact_id: string
          lead_conversion_id: string
          organization_id: string
          resolution_mode: string
          was_created: boolean
        }
        Update: {
          guardian_id?: string
          id?: string
          lead_contact_id?: string
          lead_conversion_id?: string
          organization_id?: string
          resolution_mode?: string
          was_created?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "lead_conversion_contact_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_contact_organization_id_lead_contact_id_fkey"
            columns: ["organization_id", "lead_contact_id"]
            isOneToOne: false
            referencedRelation: "lead_contact"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_contact_organization_id_lead_conversion_id_fkey"
            columns: ["organization_id", "lead_conversion_id"]
            isOneToOne: false
            referencedRelation: "lead_conversion"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_conversion_enrollment: {
        Row: {
          class_id: string
          enrollment_id: string
          id: string
          lead_candidate_id: string
          lead_conversion_id: string
          organization_id: string
        }
        Insert: {
          class_id: string
          enrollment_id: string
          id?: string
          lead_candidate_id: string
          lead_conversion_id: string
          organization_id: string
        }
        Update: {
          class_id?: string
          enrollment_id?: string
          id?: string
          lead_candidate_id?: string
          lead_conversion_id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_conversion_enrollment_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_enrollment_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_enrollment_organization_id_lead_candidate__fkey"
            columns: ["organization_id", "lead_candidate_id"]
            isOneToOne: false
            referencedRelation: "lead_candidate"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_enrollment_organization_id_lead_conversion_fkey"
            columns: ["organization_id", "lead_conversion_id"]
            isOneToOne: false
            referencedRelation: "lead_conversion"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_conversion_student_guardian: {
        Row: {
          guardian_id: string
          id: string
          is_billing_contact: boolean
          is_primary_contact: boolean
          lead_candidate_id: string
          lead_contact_id: string
          lead_conversion_id: string
          organization_id: string
          relationship_type: string
          student_guardian_id: string
          student_id: string
          was_created: boolean
          was_reused: boolean
        }
        Insert: {
          guardian_id: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          lead_candidate_id: string
          lead_contact_id: string
          lead_conversion_id: string
          organization_id: string
          relationship_type: string
          student_guardian_id: string
          student_id: string
          was_created: boolean
          was_reused: boolean
        }
        Update: {
          guardian_id?: string
          id?: string
          is_billing_contact?: boolean
          is_primary_contact?: boolean
          lead_candidate_id?: string
          lead_contact_id?: string
          lead_conversion_id?: string
          organization_id?: string
          relationship_type?: string
          student_guardian_id?: string
          student_id?: string
          was_created?: boolean
          was_reused?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "lead_conversion_student_guard_organization_id_lead_candida_fkey"
            columns: ["organization_id", "lead_candidate_id"]
            isOneToOne: false
            referencedRelation: "lead_candidate"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_student_guard_organization_id_lead_contact_fkey"
            columns: ["organization_id", "lead_contact_id"]
            isOneToOne: false
            referencedRelation: "lead_contact"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_student_guard_organization_id_lead_convers_fkey"
            columns: ["organization_id", "lead_conversion_id"]
            isOneToOne: false
            referencedRelation: "lead_conversion"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_student_guard_organization_id_student_guar_fkey"
            columns: ["organization_id", "student_guardian_id"]
            isOneToOne: false
            referencedRelation: "student_guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_student_guardi_organization_id_guardian_id_fkey"
            columns: ["organization_id", "guardian_id"]
            isOneToOne: false
            referencedRelation: "guardian"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_conversion_student_guardia_organization_id_student_id_fkey"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_follow_up: {
        Row: {
          assigned_user_id: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string
          due_at: string
          id: string
          lead_id: string
          note: string | null
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          assigned_user_id?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by: string
          due_at: string
          id?: string
          lead_id: string
          note?: string | null
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_user_id?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string
          due_at?: string
          id?: string
          lead_id?: string
          note?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_follow_up_organization_id_assigned_user_id_fkey"
            columns: ["organization_id", "assigned_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_follow_up_organization_id_cancelled_by_fkey"
            columns: ["organization_id", "cancelled_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_follow_up_organization_id_completed_by_fkey"
            columns: ["organization_id", "completed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_follow_up_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_follow_up_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_identity_resolution_event: {
        Row: {
          changed_at: string
          changed_by: string
          id: string
          new_resolution_mode: string | null
          new_target_id: string | null
          note: string | null
          organization_id: string
          previous_resolution_mode: string | null
          previous_target_id: string | null
          subject_id: string
          subject_type: string
        }
        Insert: {
          changed_at?: string
          changed_by: string
          id?: string
          new_resolution_mode?: string | null
          new_target_id?: string | null
          note?: string | null
          organization_id: string
          previous_resolution_mode?: string | null
          previous_target_id?: string | null
          subject_id: string
          subject_type: string
        }
        Update: {
          changed_at?: string
          changed_by?: string
          id?: string
          new_resolution_mode?: string | null
          new_target_id?: string | null
          note?: string | null
          organization_id?: string
          previous_resolution_mode?: string | null
          previous_target_id?: string | null
          subject_id?: string
          subject_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_identity_resolution_event_organization_id_changed_by_fkey"
            columns: ["organization_id", "changed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_lost_reason: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          display_name: string
          id: string
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          display_name: string
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          display_name?: string
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_lost_reason_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_lost_reason_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_lost_reason_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_source: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          display_name: string
          id: string
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          display_name: string
          id?: string
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          display_name?: string
          id?: string
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_source_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_source_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_source_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_status_history: {
        Row: {
          changed_at: string
          changed_by: string
          from_status: string | null
          id: string
          lead_id: string
          lost_reason_id: string | null
          notes: string | null
          organization_id: string
          to_status: string
        }
        Insert: {
          changed_at?: string
          changed_by: string
          from_status?: string | null
          id?: string
          lead_id: string
          lost_reason_id?: string | null
          notes?: string | null
          organization_id: string
          to_status: string
        }
        Update: {
          changed_at?: string
          changed_by?: string
          from_status?: string | null
          id?: string
          lead_id?: string
          lost_reason_id?: string | null
          notes?: string | null
          organization_id?: string
          to_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_status_history_organization_id_changed_by_fkey"
            columns: ["organization_id", "changed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_status_history_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_status_history_organization_id_lost_reason_id_fkey"
            columns: ["organization_id", "lost_reason_id"]
            isOneToOne: false
            referencedRelation: "lead_lost_reason"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_trial: {
        Row: {
          cancelled_at: string | null
          cancelled_by: string | null
          class_id: string
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string
          id: string
          lead_candidate_id: string
          lead_id: string
          no_show_at: string | null
          no_show_by: string | null
          operational_note: string | null
          organization_id: string
          outcome_note: string | null
          scheduled_end_at: string
          scheduled_start_at: string
          status: string
          teaching_session_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          class_id: string
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by: string
          id?: string
          lead_candidate_id: string
          lead_id: string
          no_show_at?: string | null
          no_show_by?: string | null
          operational_note?: string | null
          organization_id: string
          outcome_note?: string | null
          scheduled_end_at: string
          scheduled_start_at: string
          status?: string
          teaching_session_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          class_id?: string
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string
          id?: string
          lead_candidate_id?: string
          lead_id?: string
          no_show_at?: string | null
          no_show_by?: string | null
          operational_note?: string | null
          organization_id?: string
          outcome_note?: string | null
          scheduled_end_at?: string
          scheduled_start_at?: string
          status?: string
          teaching_session_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_trial_organization_id_cancelled_by_fkey"
            columns: ["organization_id", "cancelled_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_completed_by_fkey"
            columns: ["organization_id", "completed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_lead_candidate_id_fkey"
            columns: ["organization_id", "lead_candidate_id"]
            isOneToOne: false
            referencedRelation: "lead_candidate"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_lead_id_fkey"
            columns: ["organization_id", "lead_id"]
            isOneToOne: false
            referencedRelation: "lead"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_no_show_by_fkey"
            columns: ["organization_id", "no_show_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_teaching_session_id_fkey"
            columns: ["organization_id", "teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      lead_trial_event: {
        Row: {
          changed_by: string
          event_type: string
          id: string
          lead_trial_id: string
          new_class_id: string | null
          new_scheduled_end_at: string | null
          new_scheduled_start_at: string | null
          new_teaching_session_id: string | null
          note: string | null
          occurred_at: string
          organization_id: string
          outcome_snapshot: Json | null
          previous_class_id: string | null
          previous_scheduled_end_at: string | null
          previous_scheduled_start_at: string | null
          previous_teaching_session_id: string | null
        }
        Insert: {
          changed_by: string
          event_type: string
          id?: string
          lead_trial_id: string
          new_class_id?: string | null
          new_scheduled_end_at?: string | null
          new_scheduled_start_at?: string | null
          new_teaching_session_id?: string | null
          note?: string | null
          occurred_at?: string
          organization_id: string
          outcome_snapshot?: Json | null
          previous_class_id?: string | null
          previous_scheduled_end_at?: string | null
          previous_scheduled_start_at?: string | null
          previous_teaching_session_id?: string | null
        }
        Update: {
          changed_by?: string
          event_type?: string
          id?: string
          lead_trial_id?: string
          new_class_id?: string | null
          new_scheduled_end_at?: string | null
          new_scheduled_start_at?: string | null
          new_teaching_session_id?: string | null
          note?: string | null
          occurred_at?: string
          organization_id?: string
          outcome_snapshot?: Json | null
          previous_class_id?: string | null
          previous_scheduled_end_at?: string | null
          previous_scheduled_start_at?: string | null
          previous_teaching_session_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_trial_event_organization_id_changed_by_fkey"
            columns: ["organization_id", "changed_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_event_organization_id_lead_trial_id_fkey"
            columns: ["organization_id", "lead_trial_id"]
            isOneToOne: false
            referencedRelation: "lead_trial"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_event_organization_id_new_class_id_fkey"
            columns: ["organization_id", "new_class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_event_organization_id_new_teaching_session_id_fkey"
            columns: ["organization_id", "new_teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_event_organization_id_previous_class_id_fkey"
            columns: ["organization_id", "previous_class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "lead_trial_event_organization_id_previous_teaching_session_fkey"
            columns: ["organization_id", "previous_teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
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
          idempotency_key: string | null
          method_code: string
          notes: string | null
          organization_id: string
          paid_at: string
          payer_name_snapshot: string | null
          reference_number: string | null
          reversal_of_payment_id: string | null
          reversed_at: string | null
          status: string
          student_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          currency_code?: string
          guardian_id: string
          id?: string
          idempotency_key?: string | null
          method_code?: string
          notes?: string | null
          organization_id: string
          paid_at?: string
          payer_name_snapshot?: string | null
          reference_number?: string | null
          reversal_of_payment_id?: string | null
          reversed_at?: string | null
          status?: string
          student_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          currency_code?: string
          guardian_id?: string
          id?: string
          idempotency_key?: string | null
          method_code?: string
          notes?: string | null
          organization_id?: string
          paid_at?: string
          payer_name_snapshot?: string | null
          reference_number?: string | null
          reversal_of_payment_id?: string | null
          reversed_at?: string | null
          status?: string
          student_id?: string | null
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
          {
            foreignKeyName: "payment_reversal_of_fk"
            columns: ["organization_id", "reversal_of_payment_id"]
            isOneToOne: false
            referencedRelation: "payment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_student_fk"
            columns: ["organization_id", "student_id"]
            isOneToOne: false
            referencedRelation: "student"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      payment_allocation: {
        Row: {
          allocated_at: string
          allocation_batch_id: string | null
          amount: number
          charge_id: string
          id: string
          notes: string | null
          organization_id: string
          payment_id: string
          reversal_of_allocation_id: string | null
          reversed_at: string | null
          status: string
        }
        Insert: {
          allocated_at?: string
          allocation_batch_id?: string | null
          amount: number
          charge_id: string
          id?: string
          notes?: string | null
          organization_id: string
          payment_id: string
          reversal_of_allocation_id?: string | null
          reversed_at?: string | null
          status?: string
        }
        Update: {
          allocated_at?: string
          allocation_batch_id?: string | null
          amount?: number
          charge_id?: string
          id?: string
          notes?: string | null
          organization_id?: string
          payment_id?: string
          reversal_of_allocation_id?: string | null
          reversed_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_allocation_batch_fk"
            columns: ["organization_id", "allocation_batch_id"]
            isOneToOne: false
            referencedRelation: "payment_allocation_batch"
            referencedColumns: ["organization_id", "id"]
          },
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
          {
            foreignKeyName: "payment_allocation_reversal_of_fk"
            columns: ["organization_id", "reversal_of_allocation_id"]
            isOneToOne: false
            referencedRelation: "payment_allocation"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      payment_allocation_batch: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          operation_key: string
          organization_id: string
          payment_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          operation_key: string
          organization_id: string
          payment_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          operation_key?: string
          organization_id?: string
          payment_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_allocation_batch_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "payment_allocation_batch_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_allocation_batch_organization_id_payment_id_fkey"
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
      personnel_cost_entry: {
        Row: {
          accounting_period: string
          amount: number
          app_user_id: string | null
          class_id: string | null
          compensation_basis_code: string | null
          cost_domain_code: string
          created_at: string
          created_by: string | null
          id: string
          incurred_date: string
          organization_id: string
          source_type: string
          staff_compensation_rule_id: string | null
          status: string
          teacher_id: string | null
          teaching_session_id: string | null
          void_notes: string | null
          voided_at: string | null
          voided_by: string | null
          welfare_fund_baseline_config_id: string | null
        }
        Insert: {
          accounting_period: string
          amount: number
          app_user_id?: string | null
          class_id?: string | null
          compensation_basis_code?: string | null
          cost_domain_code: string
          created_at?: string
          created_by?: string | null
          id?: string
          incurred_date: string
          organization_id: string
          source_type: string
          staff_compensation_rule_id?: string | null
          status?: string
          teacher_id?: string | null
          teaching_session_id?: string | null
          void_notes?: string | null
          voided_at?: string | null
          voided_by?: string | null
          welfare_fund_baseline_config_id?: string | null
        }
        Update: {
          accounting_period?: string
          amount?: number
          app_user_id?: string | null
          class_id?: string | null
          compensation_basis_code?: string | null
          cost_domain_code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          incurred_date?: string
          organization_id?: string
          source_type?: string
          staff_compensation_rule_id?: string | null
          status?: string
          teacher_id?: string | null
          teaching_session_id?: string | null
          void_notes?: string | null
          voided_at?: string | null
          voided_by?: string | null
          welfare_fund_baseline_config_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "personnel_cost_entry_organization_id_app_user_id_fkey"
            columns: ["organization_id", "app_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_staff_compensation_ru_fkey"
            columns: ["organization_id", "staff_compensation_rule_id"]
            isOneToOne: false
            referencedRelation: "staff_compensation_rule"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_teaching_session_id_fkey"
            columns: ["organization_id", "teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_voided_by_fkey"
            columns: ["organization_id", "voided_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_welfare_fund_baseline_fkey"
            columns: ["organization_id", "welfare_fund_baseline_config_id"]
            isOneToOne: false
            referencedRelation: "welfare_fund_baseline_config"
            referencedColumns: ["organization_id", "id"]
          },
        ]
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
      revenue_recognition_event: {
        Row: {
          amount: number
          assessment_result_id: string | null
          created_at: string
          created_by: string | null
          enrollment_financial_terms_id: string
          enrollment_id: string
          enrollment_recognition_config_id: string
          enrollment_recognition_stage_id: string | null
          id: string
          lesson_sequence_number: number | null
          notes: string | null
          organization_id: string
          recognition_basis_code: string
          recognized_at: string
          status: string
          teaching_session_id: string | null
          voided_at: string | null
        }
        Insert: {
          amount: number
          assessment_result_id?: string | null
          created_at?: string
          created_by?: string | null
          enrollment_financial_terms_id: string
          enrollment_id: string
          enrollment_recognition_config_id: string
          enrollment_recognition_stage_id?: string | null
          id?: string
          lesson_sequence_number?: number | null
          notes?: string | null
          organization_id: string
          recognition_basis_code: string
          recognized_at?: string
          status?: string
          teaching_session_id?: string | null
          voided_at?: string | null
        }
        Update: {
          amount?: number
          assessment_result_id?: string | null
          created_at?: string
          created_by?: string | null
          enrollment_financial_terms_id?: string
          enrollment_id?: string
          enrollment_recognition_config_id?: string
          enrollment_recognition_stage_id?: string | null
          id?: string
          lesson_sequence_number?: number | null
          notes?: string | null
          organization_id?: string
          recognition_basis_code?: string
          recognized_at?: string
          status?: string
          teaching_session_id?: string | null
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "revenue_recognition_event_organization_id_assessment_resul_fkey"
            columns: ["organization_id", "assessment_result_id"]
            isOneToOne: false
            referencedRelation: "assessment_result"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_enrollment_finan_fkey"
            columns: ["organization_id", "enrollment_financial_terms_id"]
            isOneToOne: false
            referencedRelation: "enrollment_financial_terms"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_enrollment_id_fkey"
            columns: ["organization_id", "enrollment_id"]
            isOneToOne: false
            referencedRelation: "enrollment"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_enrollment_reco_fkey1"
            columns: ["organization_id", "enrollment_recognition_stage_id"]
            isOneToOne: false
            referencedRelation: "enrollment_recognition_stage"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_enrollment_recog_fkey"
            columns: ["organization_id", "enrollment_recognition_config_id"]
            isOneToOne: false
            referencedRelation: "enrollment_recognition_config"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "revenue_recognition_event_organization_id_teaching_session_fkey"
            columns: ["organization_id", "teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
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
          notes: string | null
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
          notes?: string | null
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
          notes?: string | null
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
      staff_compensation_rule: {
        Row: {
          amount: number
          app_user_id: string
          compensation_basis_code: string
          cost_domain_code: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          notes: string | null
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          amount: number
          app_user_id: string
          compensation_basis_code: string
          cost_domain_code: string
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          id?: string
          notes?: string | null
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          amount?: number
          app_user_id?: string
          compensation_basis_code?: string
          cost_domain_code?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          notes?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "staff_compensation_rule_organization_id_app_user_id_fkey"
            columns: ["organization_id", "app_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "staff_compensation_rule_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "staff_compensation_rule_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_compensation_rule_organization_id_updated_by_fkey"
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
      teacher_unavailability: {
        Row: {
          block_type: string
          created_at: string
          created_by: string | null
          effective_from: string | null
          effective_to: string | null
          end_time: string | null
          ends_at: string | null
          id: string
          organization_id: string
          reason: string | null
          start_time: string | null
          starts_at: string | null
          status: string
          teacher_id: string
          updated_at: string
          updated_by: string | null
          weekday_code: string | null
        }
        Insert: {
          block_type: string
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_to?: string | null
          end_time?: string | null
          ends_at?: string | null
          id?: string
          organization_id: string
          reason?: string | null
          start_time?: string | null
          starts_at?: string | null
          status?: string
          teacher_id: string
          updated_at?: string
          updated_by?: string | null
          weekday_code?: string | null
        }
        Update: {
          block_type?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_to?: string | null
          end_time?: string | null
          ends_at?: string | null
          id?: string
          organization_id?: string
          reason?: string | null
          start_time?: string | null
          starts_at?: string | null
          status?: string
          teacher_id?: string
          updated_at?: string
          updated_by?: string | null
          weekday_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "teacher_unavailability_created_by_fk"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_unavailability_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teacher_unavailability_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "teacher_unavailability_updated_by_fk"
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
      welfare_fund_baseline_config: {
        Row: {
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          id: string
          monthly_amount: number
          notes: string | null
          organization_id: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_to?: string | null
          id?: string
          monthly_amount: number
          notes?: string | null
          organization_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          monthly_amount?: number
          notes?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "welfare_fund_baseline_config_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "welfare_fund_baseline_config_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "welfare_fund_baseline_config_organization_id_updated_by_fkey"
            columns: ["organization_id", "updated_by"]
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
          adjustments_total: number | null
          allocated_total: number | null
          charge_id: string | null
          effective_obligation: number | null
          organization_id: string | null
          original_amount: number | null
          outstanding_balance: number | null
        }
        Insert: {
          adjustments_total?: never
          allocated_total?: never
          charge_id?: string | null
          effective_obligation?: never
          organization_id?: string | null
          original_amount?: number | null
          outstanding_balance?: never
        }
        Update: {
          adjustments_total?: never
          allocated_total?: never
          charge_id?: string | null
          effective_obligation?: never
          organization_id?: string | null
          original_amount?: number | null
          outstanding_balance?: never
        }
        Relationships: []
      }
      class_cost_allocation_detail: {
        Row: {
          accounting_period: string | null
          allocated_amount: number | null
          allocation_basis_code: string | null
          allocation_batch_id: string | null
          class_id: string | null
          class_name: string | null
          cost_allocation_rule_id: string | null
          cost_domain_code: string | null
          created_at: string | null
          created_by: string | null
          id: string | null
          organization_id: string | null
          sequence_number: number | null
          source_amount_snapshot: number | null
          source_record_id: string | null
          source_scope_code: string | null
          source_type: string | null
          status: string | null
          weight_total: number | null
          weight_value: number | null
        }
        Relationships: [
          {
            foreignKeyName: "class_cost_allocation_organization_id_allocation_batch_id_fkey"
            columns: ["organization_id", "allocation_batch_id"]
            isOneToOne: false
            referencedRelation: "class_cost_allocation_batch"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_cost_allocation_rule_fkey"
            columns: ["organization_id", "cost_allocation_rule_id"]
            isOneToOne: false
            referencedRelation: "cost_allocation_rule"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_created_by_fkey"
            columns: ["organization_id", "created_by"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "class_cost_allocation_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
        ]
      }
      personnel_cost_entry_detail: {
        Row: {
          accounting_period: string | null
          amount: number | null
          app_user_id: string | null
          attribution_type: string | null
          class_id: string | null
          compensation_basis_code: string | null
          cost_domain_code: string | null
          created_at: string | null
          id: string | null
          incurred_date: string | null
          organization_id: string | null
          source_type: string | null
          staff_compensation_rule_id: string | null
          status: string | null
          teacher_id: string | null
          teaching_session_id: string | null
          welfare_fund_baseline_config_id: string | null
        }
        Insert: {
          accounting_period?: string | null
          amount?: number | null
          app_user_id?: string | null
          attribution_type?: never
          class_id?: string | null
          compensation_basis_code?: string | null
          cost_domain_code?: string | null
          created_at?: string | null
          id?: string | null
          incurred_date?: string | null
          organization_id?: string | null
          source_type?: string | null
          staff_compensation_rule_id?: string | null
          status?: string | null
          teacher_id?: string | null
          teaching_session_id?: string | null
          welfare_fund_baseline_config_id?: string | null
        }
        Update: {
          accounting_period?: string | null
          amount?: number | null
          app_user_id?: string | null
          attribution_type?: never
          class_id?: string | null
          compensation_basis_code?: string | null
          cost_domain_code?: string | null
          created_at?: string | null
          id?: string | null
          incurred_date?: string | null
          organization_id?: string | null
          source_type?: string | null
          staff_compensation_rule_id?: string | null
          status?: string | null
          teacher_id?: string | null
          teaching_session_id?: string | null
          welfare_fund_baseline_config_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "personnel_cost_entry_organization_id_app_user_id_fkey"
            columns: ["organization_id", "app_user_id"]
            isOneToOne: false
            referencedRelation: "app_user"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_class_id_fkey"
            columns: ["organization_id", "class_id"]
            isOneToOne: false
            referencedRelation: "class"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organization"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_staff_compensation_ru_fkey"
            columns: ["organization_id", "staff_compensation_rule_id"]
            isOneToOne: false
            referencedRelation: "staff_compensation_rule"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_teacher_id_fkey"
            columns: ["organization_id", "teacher_id"]
            isOneToOne: false
            referencedRelation: "teacher"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_teaching_session_id_fkey"
            columns: ["organization_id", "teaching_session_id"]
            isOneToOne: false
            referencedRelation: "teaching_session"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "personnel_cost_entry_organization_id_welfare_fund_baseline_fkey"
            columns: ["organization_id", "welfare_fund_baseline_config_id"]
            isOneToOne: false
            referencedRelation: "welfare_fund_baseline_config"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
    }
    Functions: {
      _allocate_shared_source: {
        Args: {
          p_basis: string
          p_batch_id: string
          p_cost_domain_code: string
          p_created_by: string
          p_organization_id: string
          p_period_month: string
          p_rule_id: string
          p_source_amount: number
          p_source_record_id: string
          p_source_scope_code: string
          p_source_type: string
        }
        Returns: Json
      }
      _build_payment_details: { Args: { p_payment_id: string }; Returns: Json }
      _cb_as_anon: { Args: never; Returns: undefined }
      _cb_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _cb_as_super: { Args: never; Returns: undefined }
      _cb_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _charge_collection_status: {
        Args: { p_charge_id: string }
        Returns: string
      }
      _conversion_build_result: {
        Args: { p_conversion_id: string }
        Returns: Json
      }
      _conversion_ensure_student_guardian: {
        Args: {
          p_actor: string
          p_guardian_id: string
          p_is_billing_contact: boolean
          p_is_primary_contact: boolean
          p_relationship_type: string
          p_student_id: string
        }
        Returns: {
          student_guardian_id: string
          was_created: boolean
          was_reused: boolean
        }[]
      }
      _conversion_validate_enrollment: {
        Args: {
          p_class_id: string
          p_exclude_enrollment_id?: string
          p_start_date: string
          p_status: string
        }
        Returns: undefined
      }
      _insert_payment_allocations: {
        Args: { p_allocations: Json; p_batch_id?: string; p_payment_id: string }
        Returns: Json
      }
      _loc_as_anon: { Args: never; Returns: undefined }
      _loc_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _loc_as_super: { Args: never; Returns: undefined }
      _loc_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_as_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _m3_as_as_super: { Args: never; Returns: undefined }
      _m3_as_expect_fail: {
        Args: { sql_text: string; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_as_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_crm_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _m3_crm_as_super: { Args: never; Returns: undefined }
      _m3_crm_expect_fail: {
        Args: { sql_text: string; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_crm_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_lc_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _m3_lc_as_super: { Args: never; Returns: undefined }
      _m3_lc_expect_fail: {
        Args: { sql_text: string; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_lc_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_ow_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _m3_ow_as_super: { Args: never; Returns: undefined }
      _m3_ow_expect_fail: {
        Args: { sql_text: string; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_ow_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_tr_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _m3_tr_as_super: { Args: never; Returns: undefined }
      _m3_tr_expect_fail: {
        Args: { sql_text: string; test_name: string; test_no: number }
        Returns: undefined
      }
      _m3_tr_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _payment_allocation_status: {
        Args: { p_payment_id: string }
        Returns: string
      }
      _recognize_per_lesson_for_enrollment: {
        Args: { p_enrollment_id: string; p_teaching_session_id?: string }
        Returns: number
      }
      _recognize_stage_for_enrollment: {
        Args: { p_enrollment_id: string }
        Returns: number
      }
      _replace_enrollment_payment_schedule: {
        Args: { p_items: Json; p_mode: string; p_terms_id: string }
        Returns: undefined
      }
      _resolve_payer_name_snapshot: {
        Args: {
          p_guardian_id: string
          p_override: string
          p_student_id: string
        }
        Returns: string
      }
      _sec_as_anon: { Args: never; Returns: undefined }
      _sec_as_auth: { Args: { p_auth_id: string }; Returns: undefined }
      _sec_as_super: { Args: never; Returns: undefined }
      _sec_record: {
        Args: { passed: boolean; test_name: string; test_no: number }
        Returns: undefined
      }
      _validate_lead_catalog_refs: {
        Args: { p_campaign_id: string; p_org_id: string; p_source_id: string }
        Returns: undefined
      }
      _weekday_code_to_dow: {
        Args: { p_weekday_code: string }
        Returns: number
      }
      activate_enrollment_financial_terms: {
        Args: { p_terms_id: string }
        Returns: undefined
      }
      add_lead_activity: {
        Args: {
          p_activity_type_code: string
          p_content?: string
          p_lead_id: string
          p_metadata?: Json
          p_occurred_at?: string
        }
        Returns: string
      }
      allocate_payment: {
        Args: {
          p_allocations: Json
          p_operation_key?: string
          p_payment_id: string
        }
        Returns: Json
      }
      allocation_period_end: {
        Args: { p_period_month: string }
        Returns: string
      }
      append_lead_identity_resolution_event: {
        Args: {
          p_new_resolution_mode: string
          p_new_target_id: string
          p_note: string
          p_previous_resolution_mode: string
          p_previous_target_id: string
          p_subject_id: string
          p_subject_type: string
        }
        Returns: string
      }
      append_lead_trial_event: {
        Args: {
          p_event_type: string
          p_new_class?: string
          p_new_end?: string
          p_new_session?: string
          p_new_start?: string
          p_note?: string
          p_outcome_snapshot?: Json
          p_previous_class?: string
          p_previous_end?: string
          p_previous_session?: string
          p_previous_start?: string
          p_trial_id: string
        }
        Returns: string
      }
      apply_enrollment_tuition_correction: {
        Args: {
          p_new_net_tuition: number
          p_notes?: string
          p_reason_code?: string
          p_terms_id: string
        }
        Returns: string
      }
      assign_lead: {
        Args: {
          p_assigned_user_id?: string
          p_lead_id: string
          p_note?: string
        }
        Returns: Json
      }
      build_lead_candidate_identity_snapshot: {
        Args: {
          p_date_of_birth: string
          p_family_name: string
          p_given_name: string
        }
        Returns: Json
      }
      build_lead_contact_identity_snapshot: {
        Args: {
          p_email: string
          p_family_name: string
          p_given_name: string
          p_phone: string
        }
        Returns: Json
      }
      calculate_scenario_economics: {
        Args: { p_scenario_id: string }
        Returns: Json
      }
      cancel_lead_follow_up: {
        Args: { p_follow_up_id: string; p_note?: string }
        Returns: string
      }
      cancel_lead_trial: {
        Args: { p_note?: string; p_trial_id: string }
        Returns: Json
      }
      capital_asset_period_month: {
        Args: { p_period_number: number; p_placed_in_service: string }
        Returns: string
      }
      charge_allocated_amount: {
        Args: { p_charge_id: string }
        Returns: number
      }
      charge_effective_obligation: {
        Args: { p_charge_id: string }
        Returns: number
      }
      class_active_enrollment_count: {
        Args: { p_class_id: string; p_period_month: string }
        Returns: number
      }
      class_allocation_weight: {
        Args: { p_basis: string; p_class_id: string; p_period_month: string }
        Returns: number
      }
      class_delivered_session_count: {
        Args: { p_class_id: string; p_period_month: string }
        Returns: number
      }
      class_recognized_revenue_amount: {
        Args: { p_class_id: string; p_period_month: string }
        Returns: number
      }
      clone_class_financial_scenario: {
        Args: { p_scenario_id: string }
        Returns: string
      }
      compare_class_financial_scenarios: {
        Args: { p_class_id?: string; p_scenario_ids?: string[] }
        Returns: Json
      }
      complete_lead_follow_up: {
        Args: { p_follow_up_id: string; p_note?: string }
        Returns: string
      }
      complete_lead_trial: {
        Args: { p_outcome_note?: string; p_trial_id: string }
        Returns: Json
      }
      compute_break_even_learner_count: {
        Args: { p_total_cost: number; p_tuition_per_learner: number }
        Returns: number
      }
      compute_projected_class_total_cost: {
        Args: {
          p_depreciation: number
          p_direct_personnel: number
          p_marketing_sales: number
          p_operating_overhead: number
          p_shared_personnel: number
        }
        Returns: number
      }
      compute_projected_contribution: {
        Args: { p_revenue: number; p_total_cost: number }
        Returns: number
      }
      compute_projected_margin_percentage: {
        Args: { p_contribution: number; p_revenue: number }
        Returns: number
      }
      configure_welfare_fund_baseline: {
        Args: {
          p_effective_from: string
          p_monthly_amount: number
          p_notes?: string
        }
        Returns: string
      }
      convert_lead: {
        Args: {
          p_enrollments?: Json
          p_lead_id: string
          p_relationships?: Json
        }
        Returns: Json
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
      create_class_financial_scenario: {
        Args: {
          p_assumed_net_tuition_per_learner: number
          p_capacity_snapshot?: number
          p_class_id?: string
          p_marketing_assumption_basis?: string
          p_marketing_sales_assumption?: number
          p_monthly_depreciation_assumption?: number
          p_monthly_operating_overhead_assumption?: number
          p_monthly_shared_personnel_assumption?: number
          p_per_session_teacher_rate?: number
          p_planned_learner_count: number
          p_planned_months: number
          p_planned_session_count: number
          p_scenario_name: string
          p_staff_compensation_rule_id?: string
        }
        Returns: string
      }
      create_cost_allocation_rule: {
        Args: {
          p_allocation_basis_code: string
          p_effective_from: string
          p_notes?: string
          p_source_scope_code: string
        }
        Returns: string
      }
      create_enrollment_financial_terms: {
        Args: {
          p_agreed_tuition_amount: number
          p_agreement_date?: string
          p_discount_amount?: number
          p_enrollment_id: string
          p_notes?: string
          p_recognition_basis_code?: string
          p_tuition_plan_id?: string
        }
        Returns: string
      }
      create_lead_follow_up: {
        Args: {
          p_assigned_user_id?: string
          p_due_at: string
          p_lead_id: string
          p_note?: string
        }
        Returns: string
      }
      create_lead_with_people: {
        Args: { p_candidates: Json; p_contacts: Json; p_lead: Json }
        Returns: Json
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
      create_staff_compensation_rule: {
        Args: {
          p_amount: number
          p_app_user_id: string
          p_compensation_basis_code: string
          p_cost_domain_code: string
          p_effective_from: string
          p_notes?: string
        }
        Returns: string
      }
      current_app_user_id: { Args: never; Returns: string }
      current_organization_id: { Args: never; Returns: string }
      end_cost_allocation_rule: {
        Args: { p_effective_to: string; p_rule_id: string }
        Returns: string
      }
      end_staff_compensation_rule: {
        Args: { p_effective_to: string; p_rule_id: string }
        Returns: string
      }
      enrollment_recognition_entitlement: {
        Args: { p_terms_id: string }
        Returns: number
      }
      enrollment_recognized_revenue: {
        Args: { p_enrollment_id: string }
        Returns: number
      }
      enrollment_schedule_total: {
        Args: { p_terms_id: string }
        Returns: number
      }
      ensure_default_allocation_rules: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      finalize_class_financial_scenario: {
        Args: { p_scenario_id: string }
        Returns: Json
      }
      find_guardian_matches_for_lead_contact: {
        Args: { p_lead_contact_id: string }
        Returns: {
          email: string
          family_name: string
          given_name: string
          guardian_id: string
          match_confidence: string
          match_reasons: string[]
          phone: string
          sort_rank: number
          status: string
        }[]
      }
      find_student_matches_for_lead_candidate: {
        Args: { p_lead_candidate_id: string }
        Returns: {
          date_of_birth: string
          family_name: string
          given_name: string
          match_confidence: string
          match_reasons: string[]
          sort_rank: number
          status: string
          student_code: string
          student_id: string
        }[]
      }
      generate_depreciation_schedule: {
        Args: { p_capital_asset_id: string }
        Returns: undefined
      }
      generate_enrollment_charges: {
        Args: { p_terms_id: string }
        Returns: number
      }
      generate_personnel_costs: {
        Args: { p_period_month: string }
        Returns: Json
      }
      generate_teaching_session_personnel_cost: {
        Args: { p_teaching_session_id: string }
        Returns: Json
      }
      generate_teaching_sessions: {
        Args: {
          p_class_schedule_id: string
          p_range_end: string
          p_range_start: string
        }
        Returns: number
      }
      get_class_economics: {
        Args: { p_class_id: string; p_period_from: string; p_period_to: string }
        Returns: Json
      }
      get_class_financial_scenario: {
        Args: { p_scenario_id: string }
        Returns: Json
      }
      get_crm_attribution_report: {
        Args: { p_end_date: string; p_start_date: string }
        Returns: Json
      }
      get_enrollment_financial_summary: {
        Args: { p_enrollment_id: string }
        Returns: Json
      }
      get_enrollment_outstanding_charges: {
        Args: { p_enrollment_id: string }
        Returns: Json
      }
      get_lead_identity_resolution_status: {
        Args: { p_lead_id: string }
        Returns: Json
      }
      get_organization_cost_reconciliation: {
        Args: { p_period_month: string }
        Returns: Json
      }
      get_payment_details: { Args: { p_payment_id: string }; Returns: Json }
      get_projected_vs_actual_class_economics: {
        Args: {
          p_period_from: string
          p_period_to: string
          p_scenario_id: string
        }
        Returns: Json
      }
      has_permission: { Args: { p_code: string }; Returns: boolean }
      initialize_enrollment_per_lesson_recognition: {
        Args: { p_lesson_count: number; p_terms_id: string }
        Returns: string
      }
      installment_schedule_amount: {
        Args: {
          p_installment_count: number
          p_sequence_number: number
          p_total: number
        }
        Returns: number
      }
      is_active_app_user: { Args: never; Returns: boolean }
      is_allowed_lead_status_transition: {
        Args: { p_from_status: string; p_to_status: string }
        Returns: boolean
      }
      is_attendance_eligible_for_recognition: {
        Args: { p_status: string }
        Returns: boolean
      }
      is_class_eligible_for_allocation: {
        Args: { p_class_id: string; p_period_month: string }
        Returns: boolean
      }
      is_compensation_rule_applicable_to_month: {
        Args: {
          p_effective_from: string
          p_effective_to: string
          p_period_month: string
        }
        Returns: boolean
      }
      is_compensation_rule_effective_on: {
        Args: { p_effective_from: string; p_effective_to: string; p_on: string }
        Returns: boolean
      }
      is_eligible_identity_guardian: {
        Args: { p_guardian_id: string }
        Returns: boolean
      }
      is_eligible_identity_student: {
        Args: { p_student_id: string }
        Returns: boolean
      }
      is_eligible_lead_assignee: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      is_eligible_trial_class: {
        Args: { p_class_id: string }
        Returns: boolean
      }
      list_eligible_lead_assignees: {
        Args: never
        Returns: {
          display_name: string
          user_id: string
        }[]
      }
      list_eligible_trial_classes: {
        Args: never
        Returns: {
          class_id: string
          class_name: string
          class_status: string
        }[]
      }
      list_trial_teaching_sessions: {
        Args: { p_class_id: string }
        Returns: {
          scheduled_end_at: string
          scheduled_start_at: string
          session_id: string
          status: string
        }[]
      }
      mark_lead_trial_no_show: {
        Args: { p_note?: string; p_trial_id: string }
        Returns: Json
      }
      normalize_accounting_period: { Args: { p_date: string }; Returns: string }
      normalize_email_key: { Args: { p_email: string }; Returns: string }
      normalize_phone_digits: { Args: { p_phone: string }; Returns: string }
      normalize_recognition_basis_code: {
        Args: { p_code: string }
        Returns: string
      }
      payment_allocated_amount: {
        Args: { p_payment_id: string }
        Returns: number
      }
      post_depreciation_through: {
        Args: { p_capital_asset_id: string; p_through_month: string }
        Returns: number
      }
      recognition_lesson_amount: {
        Args: {
          p_lesson_count: number
          p_sequence_number: number
          p_total: number
        }
        Returns: number
      }
      recognize_enrollment_revenue: {
        Args: { p_enrollment_id: string }
        Returns: Json
      }
      recognize_teaching_session_revenue: {
        Args: { p_teaching_session_id: string }
        Returns: Json
      }
      record_payment: {
        Args: {
          p_allocations?: Json
          p_amount: number
          p_guardian_id: string
          p_idempotency_key?: string
          p_method_code?: string
          p_notes?: string
          p_paid_at?: string
          p_payer_name_snapshot?: string
          p_reference_number?: string
          p_student_id?: string
        }
        Returns: Json
      }
      reschedule_lead_trial: {
        Args: {
          p_class_id?: string
          p_note?: string
          p_scheduled_end_at?: string
          p_scheduled_start_at?: string
          p_teaching_session_id?: string
          p_trial_id: string
        }
        Returns: Json
      }
      resolve_allocation_rule: {
        Args: {
          p_organization_id: string
          p_period_month: string
          p_source_scope_code: string
        }
        Returns: string
      }
      resolve_capital_cost_group_id: {
        Args: { p_organization_id: string }
        Returns: string
      }
      resolve_enrollment_billing_guardian_id: {
        Args: { p_enrollment_id: string }
        Returns: string
      }
      resolve_lead_candidate_identity: {
        Args: {
          p_acknowledge_strong_match?: boolean
          p_lead_candidate_id: string
          p_note?: string
          p_resolution_mode?: string
          p_student_id?: string
        }
        Returns: Json
      }
      resolve_lead_contact_identity: {
        Args: {
          p_acknowledge_strong_match?: boolean
          p_guardian_id?: string
          p_lead_contact_id: string
          p_note?: string
          p_resolution_mode?: string
        }
        Returns: Json
      }
      resolve_lead_trial_schedule: {
        Args: {
          p_class_id: string
          p_scheduled_end_at: string
          p_scheduled_start_at: string
          p_teaching_session_id: string
        }
        Returns: {
          o_end: string
          o_start: string
        }[]
      }
      resolve_scenario_per_session_rate: {
        Args: {
          p_scenario: Database["public"]["Tables"]["class_financial_scenario"]["Row"]
        }
        Returns: number
      }
      retire_capital_asset: {
        Args: { p_capital_asset_id: string; p_retired_at?: string }
        Returns: undefined
      }
      reverse_payment: {
        Args: { p_notes?: string; p_payment_id: string }
        Returns: Json
      }
      reverse_payment_allocation: {
        Args: { p_allocation_id: string; p_notes?: string }
        Returns: Json
      }
      run_class_cost_allocation: {
        Args: { p_period_month: string }
        Returns: Json
      }
      schedule_lead_trial: {
        Args: {
          p_class_id: string
          p_lead_candidate_id: string
          p_lead_id: string
          p_note?: string
          p_scheduled_end_at?: string
          p_scheduled_start_at?: string
          p_teaching_session_id?: string
        }
        Returns: Json
      }
      seed_organization_cost_categories: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      seed_organization_lead_reference_data: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      set_enrollment_payment_schedule_custom: {
        Args: { p_schedule: Json; p_terms_id: string }
        Returns: undefined
      }
      set_enrollment_payment_schedule_deposit_remainder: {
        Args: {
          p_deposit_amount: number
          p_deposit_due_date: string
          p_remainder_due_date: string
          p_terms_id: string
        }
        Returns: undefined
      }
      set_enrollment_payment_schedule_full_upfront: {
        Args: { p_due_date: string; p_terms_id: string }
        Returns: undefined
      }
      set_enrollment_payment_schedule_installments: {
        Args: {
          p_first_due_date: string
          p_installment_count: number
          p_terms_id: string
        }
        Returns: undefined
      }
      set_enrollment_recognition_stages: {
        Args: { p_stages: Json; p_terms_id: string }
        Returns: string
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
      suggest_payment_allocation: {
        Args: {
          p_enrollment_id?: string
          p_payment_id: string
          p_student_id?: string
        }
        Returns: Json
      }
      teacher_has_unavailability: {
        Args: {
          p_range_end: string
          p_range_start: string
          p_teacher_id: string
        }
        Returns: boolean
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
      transition_lead_status: {
        Args: {
          p_lead_id: string
          p_lost_reason_id?: string
          p_notes?: string
          p_to_status: string
        }
        Returns: string
      }
      try_advance_lead_lifecycle_for_trial: {
        Args: {
          p_from_status: string
          p_lead_id: string
          p_notes?: string
          p_to_status: string
        }
        Returns: undefined
      }
      update_class_financial_scenario: {
        Args: {
          p_assumed_net_tuition_per_learner?: number
          p_marketing_assumption_basis?: string
          p_marketing_sales_assumption?: number
          p_monthly_depreciation_assumption?: number
          p_monthly_operating_overhead_assumption?: number
          p_monthly_shared_personnel_assumption?: number
          p_per_session_teacher_rate?: number
          p_planned_learner_count?: number
          p_planned_months?: number
          p_planned_session_count?: number
          p_scenario_id: string
          p_scenario_name?: string
          p_staff_compensation_rule_id?: string
        }
        Returns: string
      }
      update_draft_enrollment_financial_terms: {
        Args: {
          p_agreed_tuition_amount: number
          p_agreement_date?: string
          p_discount_amount?: number
          p_notes?: string
          p_recognition_basis_code?: string
          p_terms_id: string
          p_tuition_plan_id?: string
        }
        Returns: undefined
      }
      update_lead_operational: {
        Args: {
          p_clear_campaign?: boolean
          p_clear_source?: boolean
          p_lead_campaign_id?: string
          p_lead_id: string
          p_lead_source_id?: string
          p_notes_summary?: string
        }
        Returns: undefined
      }
      upsert_lead_campaign_catalog: {
        Args: {
          p_code: string
          p_id: string
          p_lead_source_id?: string
          p_name: string
          p_status?: string
        }
        Returns: string
      }
      upsert_lead_lost_reason_catalog: {
        Args: {
          p_code: string
          p_display_name: string
          p_id: string
          p_status?: string
        }
        Returns: string
      }
      upsert_lead_source_catalog: {
        Args: {
          p_code: string
          p_display_name: string
          p_id: string
          p_status?: string
        }
        Returns: string
      }
      validate_lead_trial_academic_refs: {
        Args: {
          p_candidate_id: string
          p_class_id: string
          p_lead_id: string
          p_teaching_session_id?: string
        }
        Returns: undefined
      }
      validate_personnel_cost_domain: {
        Args: { p_cost_domain_code: string; p_organization_id: string }
        Returns: undefined
      }
      void_class_cost_allocation_batch: {
        Args: { p_batch_id: string; p_notes?: string }
        Returns: string
      }
      void_personnel_cost_entry: {
        Args: { p_entry_id: string; p_notes?: string }
        Returns: string
      }
      void_revenue_recognition_event: {
        Args: { p_event_id: string; p_notes?: string }
        Returns: Json
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

