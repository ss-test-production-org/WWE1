import DiscourseRoute from "discourse/routes/discourse";
import { inject as service } from "@ember/service";
import ChatMessage from "discourse/plugins/chat/discourse/models/chat-message";

export default class ChatChannelThread extends DiscourseRoute {
  @service router;
  @service chatThreadsManager;
  @service chatStateManager;
  @service chat;

  async model(params) {
    return this.chatThreadsManager.find(
      this.modelFor("chat.channel").id,
      params.threadId
    );
  }

  afterModel(model) {
    this.chat.activeThread = model;
    this.chatStateManager.openSidePanel();
    this.chat.activeThread.messages = (
      this.chat.activeThread.messages || []
    ).map((message) => ChatMessage.create(message));
  }
}
