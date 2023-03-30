# frozen_string_literal: true

module Admin
  class ReportsController < Spree::Admin::BaseController
    include ReportsActions
    helper ReportsHelper

    before_action :authorize_report, only: [:show]

    # Define model class for Can? permissions
    def model_class
      Admin::ReportsController
    end

    def index
      @reports = reports.select do |report_type, _description|
        can? report_type, :report
      end
    end

    def show
      @report = report_class.new(spree_current_user, params, render: render_data?)

      if report_format.present?
        export_report
      else
        show_report
      end
    end

    private

    def export_report
      send_data render_report_as(report_format), filename: report_filename
    end

    def show_report
      assign_view_data
      render "show"
    end

    def assign_view_data
      @report_type = report_type
      @report_subtypes = report_subtypes
      @report_subtype = report_subtype
      @report_title = report_title
      @rendering_options = rendering_options
      @table = render_report_as(:html) if render_data?
      @data = Reporting::FrontendData.new(spree_current_user)
    end

    def render_data?
      request.post?
    end

    def render_report_as(format)
      if OpenFoodNetwork::FeatureToggle.enabled?(:background_reports, spree_current_user)
        job = ReportJob.perform_later(
          report_class, spree_current_user, params, format
        )
        sleep 1 until job.done?

        # This result has been rendered by Rails in safe mode already.
        job.result.html_safe # rubocop:disable Rails/OutputSafety
      else
        @report.render_as(format)
      end
    end
  end
end
