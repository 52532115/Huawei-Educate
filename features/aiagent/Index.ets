export { AiChatView } from './src/main/ets/components/AiChatView';
export { AdaptivePracticeView } from './src/main/ets/components/AdaptivePracticeView';
export { PhotoSearchView } from './src/main/ets/components/PhotoSearchView';
export { LearnerProfileView } from './src/main/ets/components/LearnerProfileView';
export {
  PhotoSearchHistoryView,
  PhotoSearchHistoryView as History
} from './src/main/ets/components/PhotoSearchHistoryView';
// The one non-UI export: the app entry schedules the retrieval index warm-up at
// start-up (`KnowledgeStore.scheduleWarmUp`). It is re-exported from here
// because this barrel is the module's only public surface, and the entry must
// not reach past it into the feature's internals.
export { KnowledgeStore } from './src/main/ets/service/KnowledgeStore';
