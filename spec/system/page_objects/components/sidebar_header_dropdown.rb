# frozen_string_literal: true

module PageObjects
  module Components
    class SidebarHeaderDropdown < PageObjects::Components::Base
      def click
        page.find(".hamburger-dropdown").click
      end

      SIDEBAR_HAMBURGER_DROPDOWN = ".sidebar-hamburger-dropdown"

      def width
        page.find(SIDEBAR_HAMBURGER_DROPDOWN).rect.width
      end

      def visible?
        page.has_css?(SIDEBAR_HAMBURGER_DROPDOWN)
      end

      def hidden?
        page.has_no_css?(SIDEBAR_HAMBURGER_DROPDOWN)
      end

      def has_no_keyboard_shortcuts_button?
        page.has_no_css?(".sidebar-footer-actions-keyboard-shortcuts")
      end

      def click_community_header_button
        find(".sidebar-section-header-button").click
      end

      def click_everything_link
        find(".sidebar-section-link-everything").click
      end

      def click_toggle_to_desktop_view_button
        find(".sidebar-footer-actions-toggle-mobile-view").click
      end
    end
  end
end
