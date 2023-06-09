import Controller from "@ember/controller";
import discourseDebounce from "discourse-common/lib/debounce";
import { ajax } from "discourse/lib/ajax";
import { cancel } from "@ember/runloop";
import { action, computed } from "@ember/object";
import { flashAjaxError } from "discourse/lib/ajax-error";
import ModalFunctionality from "discourse/mixins/modal-functionality";
import { inject as service } from "@ember/service";
export default class ChatChannelEditTitleController extends Controller.extend(
  ModalFunctionality
) {
  @service chatApi;
  editedName = "";
  editedSlug = "";
  autoGeneratedSlug = "";

  @computed("model.title", "editedName", "editedSlug")
  get isSaveDisabled() {
    return (
      (this.model.title === this.editedName &&
        this.model.slug === this.editedSlug) ||
      this.editedName?.length > this.siteSettings.max_topic_title_length
    );
  }

  onShow() {
    this.setProperties({
      editedName: this.model.title,
      editedSlug: this.model.slug,
    });
  }

  onClose() {
    this.setProperties({
      editedName: "",
      editedSlug: "",
    });
    this.clearFlash();
  }

  @action
  onSaveChatChannelName() {
    return this.chatApi
      .updateChannel(this.model.id, {
        name: this.editedName,
        slug: this.editedSlug || this.autoGeneratedSlug || this.model.slug,
      })
      .then((result) => {
        this.model.set("title", result.channel.title);
        this.send("closeModal");
      })
      .catch(flashAjaxError(this));
  }

  @action
  onChangeChatChannelName(title) {
    this.clearFlash();
    this._debouncedGenerateSlug(title);
  }

  @action
  onChangeChatChannelSlug() {
    this.clearFlash();
    this._debouncedGenerateSlug(this.editedName);
  }

  _clearAutoGeneratedSlug() {
    this.set("autoGeneratedSlug", "");
  }

  _debouncedGenerateSlug(name) {
    cancel(this.generateSlugHandler);
    this._clearAutoGeneratedSlug();
    if (!name) {
      return;
    }
    this.generateSlugHandler = discourseDebounce(
      this,
      this._generateSlug,
      name,
      300
    );
  }

  // intentionally not showing AJAX error for this, we will autogenerate
  // the slug server-side if they leave it blank
  _generateSlug(name) {
    ajax("/slugs.json", { type: "POST", data: { name } }).then((response) => {
      this.set("autoGeneratedSlug", response.slug);
    });
  }
}
