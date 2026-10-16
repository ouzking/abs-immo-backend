export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      agency_settings: {
        Row: {
          address_line: string | null;
          agency_name: string;
          default_country: string;
          default_currency: string;
          description: string | null;
          email: string | null;
          id: boolean;
          latitude: number | null;
          legal_name: string | null;
          locality_id: string | null;
          logo_path: string | null;
          longitude: number | null;
          ninea: string | null;
          opening_hours: NonNullable<Json>;
          phone: string | null;
          rccm: string | null;
          secondary_phone: string | null;
          seo_default_description: string | null;
          seo_default_title: string | null;
          social_links: NonNullable<Json>;
          tagline: string | null;
          updated_at: string;
          updated_by: string | null;
          whatsapp_phone: string | null;
        };
        ComputedFields: never;
        Insert: {
          address_line?: string | null;
          agency_name?: string;
          default_country?: string;
          default_currency?: string;
          description?: string | null;
          email?: string | null;
          id?: boolean;
          latitude?: number | null;
          legal_name?: string | null;
          locality_id?: string | null;
          logo_path?: string | null;
          longitude?: number | null;
          ninea?: string | null;
          opening_hours?: NonNullable<Json>;
          phone?: string | null;
          rccm?: string | null;
          secondary_phone?: string | null;
          seo_default_description?: string | null;
          seo_default_title?: string | null;
          social_links?: NonNullable<Json>;
          tagline?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          whatsapp_phone?: string | null;
        };
        Update: {
          address_line?: string | null;
          agency_name?: string;
          default_country?: string;
          default_currency?: string;
          description?: string | null;
          email?: string | null;
          id?: boolean;
          latitude?: number | null;
          legal_name?: string | null;
          locality_id?: string | null;
          logo_path?: string | null;
          longitude?: number | null;
          ninea?: string | null;
          opening_hours?: NonNullable<Json>;
          phone?: string | null;
          rccm?: string | null;
          secondary_phone?: string | null;
          seo_default_description?: string | null;
          seo_default_title?: string | null;
          social_links?: NonNullable<Json>;
          tagline?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          whatsapp_phone?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "agency_settings_default_country_fkey";
            columns: ["default_country"];
            isOneToOne: false;
            referencedRelation: "countries";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "agency_settings_locality_id_fkey";
            columns: ["locality_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "agency_settings_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      agents: {
        Row: {
          bio: string | null;
          created_at: string;
          display_name: string;
          is_active: boolean;
          is_public: boolean;
          job_title: string | null;
          languages: string[];
          license_number: string | null;
          photo_path: string | null;
          profile_id: string;
          public_email: string | null;
          public_phone: string | null;
          slug: string;
          updated_at: string;
          whatsapp_phone: string | null;
        };
        ComputedFields: never;
        Insert: {
          bio?: string | null;
          created_at?: string;
          display_name: string;
          is_active?: boolean;
          is_public?: boolean;
          job_title?: string | null;
          languages?: string[];
          license_number?: string | null;
          photo_path?: string | null;
          profile_id: string;
          public_email?: string | null;
          public_phone?: string | null;
          slug: string;
          updated_at?: string;
          whatsapp_phone?: string | null;
        };
        Update: {
          bio?: string | null;
          created_at?: string;
          display_name?: string;
          is_active?: boolean;
          is_public?: boolean;
          job_title?: string | null;
          languages?: string[];
          license_number?: string | null;
          photo_path?: string | null;
          profile_id?: string;
          public_email?: string | null;
          public_phone?: string | null;
          slug?: string;
          updated_at?: string;
          whatsapp_phone?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "agents_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: true;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      amenities: {
        Row: {
          category: string;
          code: string;
          icon: string | null;
          is_active: boolean;
          label: string;
          sort_order: number;
        };
        ComputedFields: never;
        Insert: {
          category: string;
          code: string;
          icon?: string | null;
          is_active?: boolean;
          label: string;
          sort_order?: number;
        };
        Update: {
          category?: string;
          code?: string;
          icon?: string | null;
          is_active?: boolean;
          label?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      app_settings: {
        Row: {
          description: string | null;
          key: string;
          updated_at: string;
          updated_by: string | null;
          value: NonNullable<Json>;
        };
        ComputedFields: never;
        Insert: {
          description?: string | null;
          key: string;
          updated_at?: string;
          updated_by?: string | null;
          value: NonNullable<Json>;
        };
        Update: {
          description?: string | null;
          key?: string;
          updated_at?: string;
          updated_by?: string | null;
          value?: NonNullable<Json>;
        };
        Relationships: [
          {
            foreignKeyName: "app_settings_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_logs: {
        Row: {
          action: string;
          actor_id: string | null;
          actor_role: string | null;
          context: NonNullable<Json>;
          id: number;
          new_data: Json | null;
          occurred_at: string;
          old_data: Json | null;
          record_id: string | null;
          table_name: string;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          actor_id?: string | null;
          actor_role?: string | null;
          context?: NonNullable<Json>;
          id?: never;
          new_data?: Json | null;
          occurred_at?: string;
          old_data?: Json | null;
          record_id?: string | null;
          table_name: string;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          actor_role?: string | null;
          context?: NonNullable<Json>;
          id?: never;
          new_data?: Json | null;
          occurred_at?: string;
          old_data?: Json | null;
          record_id?: string | null;
          table_name?: string;
        };
        Relationships: [];
      };
      countries: {
        Row: {
          code: string;
          currency_code: string;
          is_active: boolean;
          name: string;
          phone_prefix: string;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          currency_code: string;
          is_active?: boolean;
          name: string;
          phone_prefix: string;
        };
        Update: {
          code?: string;
          currency_code?: string;
          is_active?: boolean;
          name?: string;
          phone_prefix?: string;
        };
        Relationships: [];
      };
      inquiries: {
        Row: {
          answered_at: string | null;
          assigned_agent_id: string | null;
          channel: Database["public"]["Enums"]["lead_source"];
          closed_at: string | null;
          created_at: string;
          created_by: string | null;
          id: string;
          inquiry_type: Database["public"]["Enums"]["inquiry_type"];
          lead_id: string;
          message: string | null;
          property_id: string | null;
          status: Database["public"]["Enums"]["inquiry_status"];
          submission_meta: NonNullable<Json>;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          answered_at?: string | null;
          assigned_agent_id?: string | null;
          channel?: Database["public"]["Enums"]["lead_source"];
          closed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          inquiry_type?: Database["public"]["Enums"]["inquiry_type"];
          lead_id: string;
          message?: string | null;
          property_id?: string | null;
          status?: Database["public"]["Enums"]["inquiry_status"];
          submission_meta?: NonNullable<Json>;
          updated_at?: string;
        };
        Update: {
          answered_at?: string | null;
          assigned_agent_id?: string | null;
          channel?: Database["public"]["Enums"]["lead_source"];
          closed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          inquiry_type?: Database["public"]["Enums"]["inquiry_type"];
          lead_id?: string;
          message?: string | null;
          property_id?: string | null;
          status?: Database["public"]["Enums"]["inquiry_status"];
          submission_meta?: NonNullable<Json>;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "inquiries_assigned_agent_id_fkey";
            columns: ["assigned_agent_id"];
            isOneToOne: false;
            referencedRelation: "agents";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "inquiries_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "inquiries_lead_id_fkey";
            columns: ["lead_id"];
            isOneToOne: false;
            referencedRelation: "leads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "inquiries_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "inquiries_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
      lead_activities: {
        Row: {
          activity_type: Database["public"]["Enums"]["lead_activity_type"];
          actor_id: string | null;
          content: string | null;
          created_at: string;
          id: string;
          inquiry_id: string | null;
          lead_id: string;
          metadata: NonNullable<Json>;
          viewing_request_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          activity_type: Database["public"]["Enums"]["lead_activity_type"];
          actor_id?: string | null;
          content?: string | null;
          created_at?: string;
          id?: string;
          inquiry_id?: string | null;
          lead_id: string;
          metadata?: NonNullable<Json>;
          viewing_request_id?: string | null;
        };
        Update: {
          activity_type?: Database["public"]["Enums"]["lead_activity_type"];
          actor_id?: string | null;
          content?: string | null;
          created_at?: string;
          id?: string;
          inquiry_id?: string | null;
          lead_id?: string;
          metadata?: NonNullable<Json>;
          viewing_request_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "lead_activities_actor_id_fkey";
            columns: ["actor_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "lead_activities_inquiry_id_fkey";
            columns: ["inquiry_id"];
            isOneToOne: false;
            referencedRelation: "inquiries";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "lead_activities_lead_id_fkey";
            columns: ["lead_id"];
            isOneToOne: false;
            referencedRelation: "leads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "lead_activities_viewing_request_id_fkey";
            columns: ["viewing_request_id"];
            isOneToOne: false;
            referencedRelation: "viewing_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      leads: {
        Row: {
          assigned_agent_id: string | null;
          budget_max: number | null;
          budget_min: number | null;
          consent_at: string | null;
          consent_marketing: boolean;
          created_at: string;
          created_by: string | null;
          desired_locality_id: string | null;
          desired_property_type: string | null;
          desired_transaction: Database["public"]["Enums"]["transaction_type"] | null;
          email: string | null;
          full_name: string;
          id: string;
          last_activity_at: string;
          lost_reason: string | null;
          phone: string | null;
          preferred_contact: Database["public"]["Enums"]["contact_method"] | null;
          source: Database["public"]["Enums"]["lead_source"];
          status: Database["public"]["Enums"]["lead_status"];
          updated_at: string;
          whatsapp_phone: string | null;
        };
        ComputedFields: never;
        Insert: {
          assigned_agent_id?: string | null;
          budget_max?: number | null;
          budget_min?: number | null;
          consent_at?: string | null;
          consent_marketing?: boolean;
          created_at?: string;
          created_by?: string | null;
          desired_locality_id?: string | null;
          desired_property_type?: string | null;
          desired_transaction?: Database["public"]["Enums"]["transaction_type"] | null;
          email?: string | null;
          full_name: string;
          id?: string;
          last_activity_at?: string;
          lost_reason?: string | null;
          phone?: string | null;
          preferred_contact?: Database["public"]["Enums"]["contact_method"] | null;
          source?: Database["public"]["Enums"]["lead_source"];
          status?: Database["public"]["Enums"]["lead_status"];
          updated_at?: string;
          whatsapp_phone?: string | null;
        };
        Update: {
          assigned_agent_id?: string | null;
          budget_max?: number | null;
          budget_min?: number | null;
          consent_at?: string | null;
          consent_marketing?: boolean;
          created_at?: string;
          created_by?: string | null;
          desired_locality_id?: string | null;
          desired_property_type?: string | null;
          desired_transaction?: Database["public"]["Enums"]["transaction_type"] | null;
          email?: string | null;
          full_name?: string;
          id?: string;
          last_activity_at?: string;
          lost_reason?: string | null;
          phone?: string | null;
          preferred_contact?: Database["public"]["Enums"]["contact_method"] | null;
          source?: Database["public"]["Enums"]["lead_source"];
          status?: Database["public"]["Enums"]["lead_status"];
          updated_at?: string;
          whatsapp_phone?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "leads_assigned_agent_id_fkey";
            columns: ["assigned_agent_id"];
            isOneToOne: false;
            referencedRelation: "agents";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "leads_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "leads_desired_locality_id_fkey";
            columns: ["desired_locality_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "leads_desired_property_type_fkey";
            columns: ["desired_property_type"];
            isOneToOne: false;
            referencedRelation: "property_types";
            referencedColumns: ["code"];
          },
        ];
      };
      localities: {
        Row: {
          country_code: string;
          created_at: string;
          id: string;
          is_active: boolean;
          latitude: number | null;
          level: Database["public"]["Enums"]["locality_level"];
          longitude: number | null;
          name: string;
          parent_id: string | null;
          slug: string;
          sort_order: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          country_code: string;
          created_at?: string;
          id?: string;
          is_active?: boolean;
          latitude?: number | null;
          level: Database["public"]["Enums"]["locality_level"];
          longitude?: number | null;
          name: string;
          parent_id?: string | null;
          slug: string;
          sort_order?: number;
          updated_at?: string;
        };
        Update: {
          country_code?: string;
          created_at?: string;
          id?: string;
          is_active?: boolean;
          latitude?: number | null;
          level?: Database["public"]["Enums"]["locality_level"];
          longitude?: number | null;
          name?: string;
          parent_id?: string | null;
          slug?: string;
          sort_order?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "localities_country_code_fkey";
            columns: ["country_code"];
            isOneToOne: false;
            referencedRelation: "countries";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "localities_parent_id_fkey";
            columns: ["parent_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
        ];
      };
      permissions: {
        Row: {
          code: string;
          description: string;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          description: string;
        };
        Update: {
          code?: string;
          description?: string;
        };
        Relationships: [];
      };
      profiles: {
        Row: {
          avatar_path: string | null;
          created_at: string;
          deactivated_at: string | null;
          deactivated_by: string | null;
          email: string | null;
          full_name: string;
          id: string;
          is_active: boolean;
          last_sign_in_at: string | null;
          locale: string;
          phone: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          avatar_path?: string | null;
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          email?: string | null;
          full_name?: string;
          id: string;
          is_active?: boolean;
          last_sign_in_at?: string | null;
          locale?: string;
          phone?: string | null;
          updated_at?: string;
        };
        Update: {
          avatar_path?: string | null;
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          email?: string | null;
          full_name?: string;
          id?: string;
          is_active?: boolean;
          last_sign_in_at?: string | null;
          locale?: string;
          phone?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "profiles_deactivated_by_fkey";
            columns: ["deactivated_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      properties: {
        Row: {
          address_line: string | null;
          address_visibility: Database["public"]["Enums"]["address_visibility"];
          agency_fee_amount: number | null;
          agent_id: string | null;
          archived_at: string | null;
          bathrooms: number | null;
          bedrooms: number | null;
          city_id: string | null;
          commercial_status: Database["public"]["Enums"]["commercial_status"];
          commune_id: string | null;
          country_code: string;
          created_at: string;
          created_by: string | null;
          currency_code: string;
          deposit_amount: number | null;
          description: string | null;
          featured_rank: number;
          floor: number | null;
          id: string;
          internal_notes: string | null;
          is_featured: boolean;
          is_furnished: boolean | null;
          land_area: number | null;
          latitude: number | null;
          legal_status: Database["public"]["Enums"]["property_legal_status"] | null;
          locality_id: string;
          location_label: string | null;
          longitude: number | null;
          neighborhood_id: string | null;
          parking_spaces: number | null;
          price_amount: number | null;
          price_negotiable: boolean;
          price_on_request: boolean;
          property_type: string;
          publication_status: Database["public"]["Enums"]["publication_status"];
          published_at: string | null;
          reference: string;
          region_id: string | null;
          rent_period: Database["public"]["Enums"]["rent_period"] | null;
          rooms: number | null;
          search_vector: unknown;
          seo_description: string | null;
          seo_title: string | null;
          short_description: string | null;
          slug: string;
          status_changed_at: string;
          surface_area: number | null;
          surface_unit: Database["public"]["Enums"]["surface_unit"];
          title: string;
          toilets: number | null;
          total_floors: number | null;
          transaction_type: Database["public"]["Enums"]["transaction_type"];
          unpublished_at: string | null;
          updated_at: string;
          year_built: number | null;
        };
        ComputedFields: never;
        Insert: {
          address_line?: string | null;
          address_visibility?: Database["public"]["Enums"]["address_visibility"];
          agency_fee_amount?: number | null;
          agent_id?: string | null;
          archived_at?: string | null;
          bathrooms?: number | null;
          bedrooms?: number | null;
          city_id?: string | null;
          commercial_status?: Database["public"]["Enums"]["commercial_status"];
          commune_id?: string | null;
          country_code?: string;
          created_at?: string;
          created_by?: string | null;
          currency_code?: string;
          deposit_amount?: number | null;
          description?: string | null;
          featured_rank?: number;
          floor?: number | null;
          id?: string;
          internal_notes?: string | null;
          is_featured?: boolean;
          is_furnished?: boolean | null;
          land_area?: number | null;
          latitude?: number | null;
          legal_status?: Database["public"]["Enums"]["property_legal_status"] | null;
          locality_id: string;
          location_label?: string | null;
          longitude?: number | null;
          neighborhood_id?: string | null;
          parking_spaces?: number | null;
          price_amount?: number | null;
          price_negotiable?: boolean;
          price_on_request?: boolean;
          property_type: string;
          publication_status?: Database["public"]["Enums"]["publication_status"];
          published_at?: string | null;
          reference?: string;
          region_id?: string | null;
          rent_period?: Database["public"]["Enums"]["rent_period"] | null;
          rooms?: number | null;
          search_vector?: unknown;
          seo_description?: string | null;
          seo_title?: string | null;
          short_description?: string | null;
          slug?: string;
          status_changed_at?: string;
          surface_area?: number | null;
          surface_unit?: Database["public"]["Enums"]["surface_unit"];
          title: string;
          toilets?: number | null;
          total_floors?: number | null;
          transaction_type: Database["public"]["Enums"]["transaction_type"];
          unpublished_at?: string | null;
          updated_at?: string;
          year_built?: number | null;
        };
        Update: {
          address_line?: string | null;
          address_visibility?: Database["public"]["Enums"]["address_visibility"];
          agency_fee_amount?: number | null;
          agent_id?: string | null;
          archived_at?: string | null;
          bathrooms?: number | null;
          bedrooms?: number | null;
          city_id?: string | null;
          commercial_status?: Database["public"]["Enums"]["commercial_status"];
          commune_id?: string | null;
          country_code?: string;
          created_at?: string;
          created_by?: string | null;
          currency_code?: string;
          deposit_amount?: number | null;
          description?: string | null;
          featured_rank?: number;
          floor?: number | null;
          id?: string;
          internal_notes?: string | null;
          is_featured?: boolean;
          is_furnished?: boolean | null;
          land_area?: number | null;
          latitude?: number | null;
          legal_status?: Database["public"]["Enums"]["property_legal_status"] | null;
          locality_id?: string;
          location_label?: string | null;
          longitude?: number | null;
          neighborhood_id?: string | null;
          parking_spaces?: number | null;
          price_amount?: number | null;
          price_negotiable?: boolean;
          price_on_request?: boolean;
          property_type?: string;
          publication_status?: Database["public"]["Enums"]["publication_status"];
          published_at?: string | null;
          reference?: string;
          region_id?: string | null;
          rent_period?: Database["public"]["Enums"]["rent_period"] | null;
          rooms?: number | null;
          search_vector?: unknown;
          seo_description?: string | null;
          seo_title?: string | null;
          short_description?: string | null;
          slug?: string;
          status_changed_at?: string;
          surface_area?: number | null;
          surface_unit?: Database["public"]["Enums"]["surface_unit"];
          title?: string;
          toilets?: number | null;
          total_floors?: number | null;
          transaction_type?: Database["public"]["Enums"]["transaction_type"];
          unpublished_at?: string | null;
          updated_at?: string;
          year_built?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "properties_agent_id_fkey";
            columns: ["agent_id"];
            isOneToOne: false;
            referencedRelation: "agents";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "properties_city_id_fkey";
            columns: ["city_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_commune_id_fkey";
            columns: ["commune_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_country_code_fkey";
            columns: ["country_code"];
            isOneToOne: false;
            referencedRelation: "countries";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "properties_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_locality_id_fkey";
            columns: ["locality_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_neighborhood_id_fkey";
            columns: ["neighborhood_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_property_type_fkey";
            columns: ["property_type"];
            isOneToOne: false;
            referencedRelation: "property_types";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "properties_region_id_fkey";
            columns: ["region_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
        ];
      };
      property_amenities: {
        Row: {
          amenity_code: string;
          property_id: string;
        };
        ComputedFields: never;
        Insert: {
          amenity_code: string;
          property_id: string;
        };
        Update: {
          amenity_code?: string;
          property_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "property_amenities_amenity_code_fkey";
            columns: ["amenity_code"];
            isOneToOne: false;
            referencedRelation: "amenities";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "property_amenities_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_amenities_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
      property_documents: {
        Row: {
          created_at: string;
          document_type: Database["public"]["Enums"]["property_document_type"];
          id: string;
          mime_type: string | null;
          property_id: string;
          size_bytes: number | null;
          storage_path: string;
          title: string;
          uploaded_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          document_type?: Database["public"]["Enums"]["property_document_type"];
          id?: string;
          mime_type?: string | null;
          property_id: string;
          size_bytes?: number | null;
          storage_path: string;
          title: string;
          uploaded_by?: string | null;
        };
        Update: {
          created_at?: string;
          document_type?: Database["public"]["Enums"]["property_document_type"];
          id?: string;
          mime_type?: string | null;
          property_id?: string;
          size_bytes?: number | null;
          storage_path?: string;
          title?: string;
          uploaded_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "property_documents_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_documents_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_documents_uploaded_by_fkey";
            columns: ["uploaded_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      property_features: {
        Row: {
          created_at: string;
          id: string;
          label: string;
          property_id: string;
          sort_order: number;
          value: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          label: string;
          property_id: string;
          sort_order?: number;
          value?: string | null;
        };
        Update: {
          created_at?: string;
          id?: string;
          label?: string;
          property_id?: string;
          sort_order?: number;
          value?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "property_features_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_features_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
      property_media: {
        Row: {
          alt_text: string | null;
          created_at: string;
          created_by: string | null;
          height: number | null;
          id: string;
          is_cover: boolean;
          mime_type: string | null;
          property_id: string;
          size_bytes: number | null;
          sort_order: number;
          storage_path: string;
          updated_at: string;
          width: number | null;
        };
        ComputedFields: never;
        Insert: {
          alt_text?: string | null;
          created_at?: string;
          created_by?: string | null;
          height?: number | null;
          id?: string;
          is_cover?: boolean;
          mime_type?: string | null;
          property_id: string;
          size_bytes?: number | null;
          sort_order?: number;
          storage_path: string;
          updated_at?: string;
          width?: number | null;
        };
        Update: {
          alt_text?: string | null;
          created_at?: string;
          created_by?: string | null;
          height?: number | null;
          id?: string;
          is_cover?: boolean;
          mime_type?: string | null;
          property_id?: string;
          size_bytes?: number | null;
          sort_order?: number;
          storage_path?: string;
          updated_at?: string;
          width?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "property_media_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_media_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_media_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
      property_types: {
        Row: {
          code: string;
          is_active: boolean;
          is_land: boolean;
          label: string;
          label_plural: string;
          sort_order: number;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          is_active?: boolean;
          is_land?: boolean;
          label: string;
          label_plural: string;
          sort_order?: number;
        };
        Update: {
          code?: string;
          is_active?: boolean;
          is_land?: boolean;
          label?: string;
          label_plural?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      role_permissions: {
        Row: {
          permission_code: string;
          role_code: string;
        };
        ComputedFields: never;
        Insert: {
          permission_code: string;
          role_code: string;
        };
        Update: {
          permission_code?: string;
          role_code?: string;
        };
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_code_fkey";
            columns: ["permission_code"];
            isOneToOne: false;
            referencedRelation: "permissions";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "role_permissions_role_code_fkey";
            columns: ["role_code"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["code"];
          },
        ];
      };
      roles: {
        Row: {
          code: string;
          description: string | null;
          label: string;
          rank: number;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          description?: string | null;
          label: string;
          rank: number;
        };
        Update: {
          code?: string;
          description?: string | null;
          label?: string;
          rank?: number;
        };
        Relationships: [];
      };
      user_roles: {
        Row: {
          granted_at: string;
          granted_by: string | null;
          role_code: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          granted_at?: string;
          granted_by?: string | null;
          role_code: string;
          user_id: string;
        };
        Update: {
          granted_at?: string;
          granted_by?: string | null;
          role_code?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_roles_granted_by_fkey";
            columns: ["granted_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_roles_role_code_fkey";
            columns: ["role_code"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "user_roles_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      viewing_requests: {
        Row: {
          alternative_date: string | null;
          assigned_agent_id: string | null;
          cancellation_reason: string | null;
          completed_at: string | null;
          created_at: string;
          created_by: string | null;
          id: string;
          lead_id: string;
          message: string | null;
          outcome_notes: string | null;
          preferred_date: string | null;
          preferred_time_slot: Database["public"]["Enums"]["time_slot"];
          property_id: string | null;
          scheduled_at: string | null;
          status: Database["public"]["Enums"]["viewing_status"];
          submission_meta: NonNullable<Json>;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          alternative_date?: string | null;
          assigned_agent_id?: string | null;
          cancellation_reason?: string | null;
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          lead_id: string;
          message?: string | null;
          outcome_notes?: string | null;
          preferred_date?: string | null;
          preferred_time_slot?: Database["public"]["Enums"]["time_slot"];
          property_id?: string | null;
          scheduled_at?: string | null;
          status?: Database["public"]["Enums"]["viewing_status"];
          submission_meta?: NonNullable<Json>;
          updated_at?: string;
        };
        Update: {
          alternative_date?: string | null;
          assigned_agent_id?: string | null;
          cancellation_reason?: string | null;
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          lead_id?: string;
          message?: string | null;
          outcome_notes?: string | null;
          preferred_date?: string | null;
          preferred_time_slot?: Database["public"]["Enums"]["time_slot"];
          property_id?: string | null;
          scheduled_at?: string | null;
          status?: Database["public"]["Enums"]["viewing_status"];
          submission_meta?: NonNullable<Json>;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "viewing_requests_assigned_agent_id_fkey";
            columns: ["assigned_agent_id"];
            isOneToOne: false;
            referencedRelation: "agents";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "viewing_requests_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "viewing_requests_lead_id_fkey";
            columns: ["lead_id"];
            isOneToOne: false;
            referencedRelation: "leads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "viewing_requests_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "viewing_requests_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      public_agents: {
        Row: {
          bio: string | null;
          display_name: string | null;
          job_title: string | null;
          languages: string[] | null;
          photo_path: string | null;
          public_email: string | null;
          public_phone: string | null;
          published_property_count: number | null;
          slug: string | null;
          whatsapp_phone: string | null;
        };
        ComputedFields: never;
        Relationships: [];
      };
      public_properties: {
        Row: {
          address_line: string | null;
          agency_fee_amount: number | null;
          agent: Json | null;
          amenity_codes: string[] | null;
          bathrooms: number | null;
          bedrooms: number | null;
          city_id: string | null;
          city_name: string | null;
          city_slug: string | null;
          commercial_status: Database["public"]["Enums"]["commercial_status"] | null;
          commune_id: string | null;
          commune_name: string | null;
          commune_slug: string | null;
          country_code: string | null;
          cover_image_alt: string | null;
          cover_image_path: string | null;
          currency_code: string | null;
          deposit_amount: number | null;
          description: string | null;
          featured_rank: number | null;
          floor: number | null;
          id: string | null;
          image_count: number | null;
          is_featured: boolean | null;
          is_furnished: boolean | null;
          land_area: number | null;
          latitude: number | null;
          legal_status: Database["public"]["Enums"]["property_legal_status"] | null;
          location_label: string | null;
          location_precision: Database["public"]["Enums"]["address_visibility"] | null;
          longitude: number | null;
          neighborhood_id: string | null;
          neighborhood_name: string | null;
          neighborhood_slug: string | null;
          parking_spaces: number | null;
          price_amount: number | null;
          price_negotiable: boolean | null;
          price_on_request: boolean | null;
          property_type: string | null;
          property_type_label: string | null;
          published_at: string | null;
          reference: string | null;
          region_id: string | null;
          region_name: string | null;
          region_slug: string | null;
          rent_period: Database["public"]["Enums"]["rent_period"] | null;
          rooms: number | null;
          search_vector: unknown;
          seo_description: string | null;
          seo_title: string | null;
          short_description: string | null;
          slug: string | null;
          surface_area: number | null;
          surface_unit: Database["public"]["Enums"]["surface_unit"] | null;
          title: string | null;
          toilets: number | null;
          total_floors: number | null;
          transaction_type: Database["public"]["Enums"]["transaction_type"] | null;
          updated_at: string | null;
          year_built: number | null;
        };
        ComputedFields: never;
        Relationships: [
          {
            foreignKeyName: "properties_city_id_fkey";
            columns: ["city_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_commune_id_fkey";
            columns: ["commune_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_country_code_fkey";
            columns: ["country_code"];
            isOneToOne: false;
            referencedRelation: "countries";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "properties_neighborhood_id_fkey";
            columns: ["neighborhood_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "properties_property_type_fkey";
            columns: ["property_type"];
            isOneToOne: false;
            referencedRelation: "property_types";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "properties_region_id_fkey";
            columns: ["region_id"];
            isOneToOne: false;
            referencedRelation: "localities";
            referencedColumns: ["id"];
          },
        ];
      };
      public_property_media: {
        Row: {
          alt_text: string | null;
          height: number | null;
          id: string | null;
          is_cover: boolean | null;
          property_id: string | null;
          sort_order: number | null;
          storage_path: string | null;
          width: number | null;
        };
        ComputedFields: never;
        Relationships: [
          {
            foreignKeyName: "property_media_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "properties";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "property_media_property_id_fkey";
            columns: ["property_id"];
            isOneToOne: false;
            referencedRelation: "public_properties";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Functions: {
      admin_set_user_active: { Args: { p_active: boolean; p_user_id: string }; Returns: undefined };
      assign_lead: {
        Args: { p_agent_id: string; p_include_open_requests?: boolean; p_lead_id: string };
        Returns: undefined;
      };
      assign_role: { Args: { p_role_code: string; p_user_id: string }; Returns: undefined };
      get_agent_performance: {
        Args: { p_from?: string; p_to?: string };
        Returns: {
          activities_logged: number;
          agent_id: string;
          display_name: string;
          inquiries_answered: number;
          inquiries_received: number;
          is_active: boolean;
          leads_assigned_open: number;
          leads_won: number;
          properties_published: number;
          properties_total: number;
          rented_in_period: number;
          sold_in_period: number;
          viewings_completed: number;
          viewings_requested: number;
        }[];
      };
      get_dashboard_stats: {
        Args: { p_agent_id?: string; p_from?: string; p_to?: string };
        Returns: Json;
      };
      get_inquiry_timeseries: {
        Args: { p_agent_id?: string; p_from?: string; p_interval?: string; p_to?: string };
        Returns: {
          bucket: string;
          inquiries: number;
          new_leads: number;
          viewing_requests: number;
        }[];
      };
      get_my_access: { Args: Record<PropertyKey, never>; Returns: Json };
      get_public_filters: { Args: Record<PropertyKey, never>; Returns: Json };
      get_public_property: { Args: { p_reference?: string; p_slug?: string }; Returns: Json };
      get_similar_properties: {
        Args: { p_limit?: number; p_property_id: string };
        Returns: {
          address_line: string | null;
          agency_fee_amount: number | null;
          agent: Json | null;
          amenity_codes: string[] | null;
          bathrooms: number | null;
          bedrooms: number | null;
          city_id: string | null;
          city_name: string | null;
          city_slug: string | null;
          commercial_status: Database["public"]["Enums"]["commercial_status"] | null;
          commune_id: string | null;
          commune_name: string | null;
          commune_slug: string | null;
          country_code: string | null;
          cover_image_alt: string | null;
          cover_image_path: string | null;
          currency_code: string | null;
          deposit_amount: number | null;
          description: string | null;
          featured_rank: number | null;
          floor: number | null;
          id: string | null;
          image_count: number | null;
          is_featured: boolean | null;
          is_furnished: boolean | null;
          land_area: number | null;
          latitude: number | null;
          legal_status: Database["public"]["Enums"]["property_legal_status"] | null;
          location_label: string | null;
          location_precision: Database["public"]["Enums"]["address_visibility"] | null;
          longitude: number | null;
          neighborhood_id: string | null;
          neighborhood_name: string | null;
          neighborhood_slug: string | null;
          parking_spaces: number | null;
          price_amount: number | null;
          price_negotiable: boolean | null;
          price_on_request: boolean | null;
          property_type: string | null;
          property_type_label: string | null;
          published_at: string | null;
          reference: string | null;
          region_id: string | null;
          region_name: string | null;
          region_slug: string | null;
          rent_period: Database["public"]["Enums"]["rent_period"] | null;
          rooms: number | null;
          search_vector: unknown;
          seo_description: string | null;
          seo_title: string | null;
          short_description: string | null;
          slug: string | null;
          surface_area: number | null;
          surface_unit: Database["public"]["Enums"]["surface_unit"] | null;
          title: string | null;
          toilets: number | null;
          total_floors: number | null;
          transaction_type: Database["public"]["Enums"]["transaction_type"] | null;
          updated_at: string | null;
          year_built: number | null;
        }[];
        SetofOptions: {
          from: "*";
          to: "public_properties";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      list_users: {
        Args: Record<PropertyKey, never>;
        Returns: {
          can_manage: boolean;
          created_at: string;
          email: string;
          full_name: string;
          id: string;
          is_active: boolean;
          is_agent: boolean;
          last_sign_in_at: string;
          phone: string;
          rank: number;
          roles: string[];
        }[];
      };
      reorder_property_media: {
        Args: { p_media_ids: string[]; p_property_id: string };
        Returns: undefined;
      };
      revoke_role: { Args: { p_role_code: string; p_user_id: string }; Returns: undefined };
      search_properties: {
        Args: {
          p_amenities?: string[];
          p_city_id?: string;
          p_commercial_statuses?: Database["public"]["Enums"]["commercial_status"][];
          p_commune_id?: string;
          p_featured_only?: boolean;
          p_furnished?: boolean;
          p_max_price?: number;
          p_max_surface?: number;
          p_min_bathrooms?: number;
          p_min_bedrooms?: number;
          p_min_price?: number;
          p_min_surface?: number;
          p_neighborhood_id?: string;
          p_property_types?: string[];
          p_query?: string;
          p_region_id?: string;
          p_sort?: string;
          p_transaction_type?: Database["public"]["Enums"]["transaction_type"];
        };
        Returns: {
          address_line: string | null;
          agency_fee_amount: number | null;
          agent: Json | null;
          amenity_codes: string[] | null;
          bathrooms: number | null;
          bedrooms: number | null;
          city_id: string | null;
          city_name: string | null;
          city_slug: string | null;
          commercial_status: Database["public"]["Enums"]["commercial_status"] | null;
          commune_id: string | null;
          commune_name: string | null;
          commune_slug: string | null;
          country_code: string | null;
          cover_image_alt: string | null;
          cover_image_path: string | null;
          currency_code: string | null;
          deposit_amount: number | null;
          description: string | null;
          featured_rank: number | null;
          floor: number | null;
          id: string | null;
          image_count: number | null;
          is_featured: boolean | null;
          is_furnished: boolean | null;
          land_area: number | null;
          latitude: number | null;
          legal_status: Database["public"]["Enums"]["property_legal_status"] | null;
          location_label: string | null;
          location_precision: Database["public"]["Enums"]["address_visibility"] | null;
          longitude: number | null;
          neighborhood_id: string | null;
          neighborhood_name: string | null;
          neighborhood_slug: string | null;
          parking_spaces: number | null;
          price_amount: number | null;
          price_negotiable: boolean | null;
          price_on_request: boolean | null;
          property_type: string | null;
          property_type_label: string | null;
          published_at: string | null;
          reference: string | null;
          region_id: string | null;
          region_name: string | null;
          region_slug: string | null;
          rent_period: Database["public"]["Enums"]["rent_period"] | null;
          rooms: number | null;
          search_vector: unknown;
          seo_description: string | null;
          seo_title: string | null;
          short_description: string | null;
          slug: string | null;
          surface_area: number | null;
          surface_unit: Database["public"]["Enums"]["surface_unit"] | null;
          title: string | null;
          toilets: number | null;
          total_floors: number | null;
          transaction_type: Database["public"]["Enums"]["transaction_type"] | null;
          updated_at: string | null;
          year_built: number | null;
        }[];
        SetofOptions: {
          from: "*";
          to: "public_properties";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      set_property_amenities: {
        Args: { p_amenity_codes: string[]; p_property_id: string };
        Returns: undefined;
      };
      submit_inquiry: {
        Args: {
          p_consent_marketing?: boolean;
          p_email?: string;
          p_full_name: string;
          p_inquiry_type?: Database["public"]["Enums"]["inquiry_type"];
          p_ip_hash?: string;
          p_message?: string;
          p_phone?: string;
          p_preferred_contact?: Database["public"]["Enums"]["contact_method"];
          p_property_id?: string;
          p_submission_meta?: Json;
        };
        Returns: Json;
      };
      submit_viewing_request: {
        Args: {
          p_alternative_date?: string;
          p_consent_marketing?: boolean;
          p_email?: string;
          p_full_name: string;
          p_ip_hash?: string;
          p_message?: string;
          p_phone?: string;
          p_preferred_contact?: Database["public"]["Enums"]["contact_method"];
          p_preferred_date?: string;
          p_preferred_time_slot?: Database["public"]["Enums"]["time_slot"];
          p_property_id: string;
          p_submission_meta?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      address_visibility: "hidden" | "approximate" | "exact";
      commercial_status: "available" | "reserved" | "sold" | "rented";
      contact_method: "phone" | "whatsapp" | "email";
      inquiry_status: "new" | "in_progress" | "answered" | "closed" | "spam";
      inquiry_type:
        | "general"
        | "property_info"
        | "price"
        | "availability"
        | "sell_property"
        | "rent_out_property"
        | "other";
      lead_activity_type:
        | "note"
        | "call"
        | "email"
        | "whatsapp"
        | "sms"
        | "meeting"
        | "visit"
        | "status_change"
        | "assignment"
        | "inquiry_received"
        | "viewing_requested"
        | "system";
      lead_source:
        | "website"
        | "whatsapp"
        | "phone"
        | "email"
        | "walk_in"
        | "facebook"
        | "instagram"
        | "referral"
        | "partner"
        | "other";
      lead_status:
        | "new"
        | "contacted"
        | "qualified"
        | "visit_scheduled"
        | "negotiation"
        | "won"
        | "lost";
      locality_level: "region" | "city" | "commune" | "neighborhood";
      property_document_type:
        | "title_deed"
        | "mandate"
        | "contract"
        | "plan"
        | "tax"
        | "identity"
        | "other";
      property_legal_status: "titre_foncier" | "bail" | "deliberation" | "permis_occuper" | "autre";
      publication_status: "draft" | "pending_review" | "published" | "unpublished" | "archived";
      rent_period: "day" | "week" | "month" | "year";
      surface_unit: "sqm" | "are" | "hectare";
      time_slot: "morning" | "afternoon" | "evening" | "any";
      transaction_type: "sale" | "rent";
      viewing_status: "requested" | "confirmed" | "completed" | "cancelled" | "no_show";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      address_visibility: ["hidden", "approximate", "exact"],
      commercial_status: ["available", "reserved", "sold", "rented"],
      contact_method: ["phone", "whatsapp", "email"],
      inquiry_status: ["new", "in_progress", "answered", "closed", "spam"],
      inquiry_type: [
        "general",
        "property_info",
        "price",
        "availability",
        "sell_property",
        "rent_out_property",
        "other",
      ],
      lead_activity_type: [
        "note",
        "call",
        "email",
        "whatsapp",
        "sms",
        "meeting",
        "visit",
        "status_change",
        "assignment",
        "inquiry_received",
        "viewing_requested",
        "system",
      ],
      lead_source: [
        "website",
        "whatsapp",
        "phone",
        "email",
        "walk_in",
        "facebook",
        "instagram",
        "referral",
        "partner",
        "other",
      ],
      lead_status: [
        "new",
        "contacted",
        "qualified",
        "visit_scheduled",
        "negotiation",
        "won",
        "lost",
      ],
      locality_level: ["region", "city", "commune", "neighborhood"],
      property_document_type: [
        "title_deed",
        "mandate",
        "contract",
        "plan",
        "tax",
        "identity",
        "other",
      ],
      property_legal_status: ["titre_foncier", "bail", "deliberation", "permis_occuper", "autre"],
      publication_status: ["draft", "pending_review", "published", "unpublished", "archived"],
      rent_period: ["day", "week", "month", "year"],
      surface_unit: ["sqm", "are", "hectare"],
      time_slot: ["morning", "afternoon", "evening", "any"],
      transaction_type: ["sale", "rent"],
      viewing_status: ["requested", "confirmed", "completed", "cancelled", "no_show"],
    },
  },
} as const;
