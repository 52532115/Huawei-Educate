import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

interface HistoryItem {
  id: number;
  question: string;
  answer: string;
}

interface HistoryListResponse {
  code: number;
  data: HistoryItem[];
  total: number;
  page: number;
  page_size: number;
}

@Component
export struct History {
  @State historyList: HistoryItem[] = []
  @State searchKeyword: string = ''
  @State isLoading: boolean = false
  @State currentPage: number = 1
  @State totalCount: number = 0
  @State pageSize: number = 20
  @State isSearching: boolean = false

  build() {
    NavDestination() {
      Column() {
        Row() {
          Button() {
            Text('←')
              .fontSize(24)
              .fontColor('#1A1A1A')
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            let pathStack = AppStorage.get<NavPathStack>('pathStack');
            if (pathStack) {
              pathStack.pop();
            }
          })

          Text('📋 搜题历史')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .margin({ left: 12 })

          Blank()

          if (this.historyList.length > 0) {
            Button() {
              Text('清空')
                .fontSize(14)
                .fontColor('#FF4D4F')
            }
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showClearConfirm()
            })
          }
        }
        .width('100%')
        .padding({ top: 20, bottom: 16, left: 16, right: 16 })
        .backgroundColor(Color.White)
        .shadow({ radius: 4, color: '#08000000', offsetY: 2 })

        Column() {
          Row() {
            Text('🔍')
              .fontSize(18)
              .margin({ right: 8 })
            TextInput({ placeholder: '搜索历史题目...', text: this.searchKeyword })
              .layoutWeight(1)
              .fontSize(15)
              .backgroundColor('#F7F9FC')
              .borderRadius(20)
              .height(40)
              .onChange((value: string) => {
                this.searchKeyword = value
              })

            if (this.searchKeyword) {
              Button() {
                Text('✕')
                  .fontSize(16)
                  .fontColor('#909399')
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .margin({ left: 8 })
              .onClick(() => {
                this.searchKeyword = ''
                this.loadHistory()
              })
            }
          }
          .width('100%')

          Button() {
            Text(this.isSearching ? '搜索中...' : '搜索')
              .fontSize(15)
              .fontColor(Color.White)
          }
          .width('100%')
          .height(44)
          .margin({ top: 12 })
          .backgroundColor(this.searchKeyword ? '#007DFF' : '#A0AEC0')
          .borderRadius(22)
          .enabled(this.searchKeyword.length > 0 && !this.isSearching)
          .onClick(() => {
            this.searchHistory()
          })
        }
        .width('92%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .margin({ top: 16 })
        .shadow({ radius: 8, color: '#08000000', offsetY: 2 })

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color('#007DFF')
            Text('加载中...')
              .fontSize(14)
              .fontColor('#909399')
              .margin({ top: 12 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.historyList.length === 0) {
          Column() {
            Text('📭')
              .fontSize(64)
              .margin({ bottom: 16 })
            Text('暂无搜题历史')
              .fontSize(16)
              .fontColor('#909399')
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              ForEach(this.historyList, (item: HistoryItem) => {
                this.buildHistoryItem(item)
              })
            }
            .width('100%')
            .padding({ top: 8, bottom: 20 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#F0F4F8')
      .onAppear(() => {
        this.loadHistory()
      })
    }
    .hideTitleBar(true)
  }

  @Builder
  buildHistoryItem(item: HistoryItem) {
    Column() {
      Row() {
        Text('❓')
          .fontSize(16)
          .margin({ right: 8 })
        Text(item.question)
          .fontSize(15)
          .fontColor('#1A1A1A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Blank()
        Button() {
          Text('🗑️')
            .fontSize(16)
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showDeleteConfirm(item.id)
        })
      }
      .width('100%')

      Row() {
        Text('💡')
          .fontSize(14)
          .margin({ right: 8 })
        Text(item.answer)
          .fontSize(13)
          .fontColor('#666666')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 8, bottom: 4 })

      Divider()
        .color('#F0F0F0')
        .margin({ top: 8 })
    }
    .width('92%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({ radius: 4, color: '#08000000', offsetY: 1 })
    .onClick(() => {
      this.showDetail(item)
    })
  }

  async loadHistory() {
    this.isLoading = true
    this.isSearching = false

    try {
      let httpRequest = http.createHttp()
      let url = `http://10.0.2.2:8000/api/history/list?page=${this.currentPage}&page_size=${this.pageSize}`
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      })

      if (response.responseCode === 200) {
        let result = JSON.parse(response.result as string) as HistoryListResponse
        if (result.code === 200) {
          this.historyList = result.data
          this.totalCount = result.total
        }
      }
    } catch (err) {
      console.error('Load history failed: ' + JSON.stringify(err))
      promptAction.showToast({ message: '加载失败，请检查网络' })
    } finally {
      this.isLoading = false
    }
  }

  async searchHistory() {
    if (!this.searchKeyword.trim()) {
      return
    }

    this.isSearching = true
    this.isLoading = true

    try {
      let httpRequest = http.createHttp()
      let url = `http://10.0.2.2:8000/api/history/search?keyword=${encodeURIComponent(this.searchKeyword)}&page=${this.currentPage}&page_size=${this.pageSize}`
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      })

      if (response.responseCode === 200) {
        let result = JSON.parse(response.result as string) as HistoryListResponse
        if (result.code === 200) {
          this.historyList = result.data
          this.totalCount = result.total
          if (this.historyList.length === 0) {
            promptAction.showToast({ message: '未找到匹配的记录' })
          }
        }
      }
    } catch (err) {
      console.error('Search history failed: ' + JSON.stringify(err))
      promptAction.showToast({ message: '搜索失败，请检查网络' })
    } finally {
      this.isSearching = false
      this.isLoading = false
    }
  }

  async deleteHistoryItem(id: number) {
    try {
      let httpRequest = http.createHttp()
      let url = `http://10.0.2.2:8000/api/history/${id}`
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      })

      if (response.responseCode === 200) {
        promptAction.showToast({ message: '删除成功' })
        if (this.searchKeyword) {
          this.searchHistory()
        } else {
          this.loadHistory()
        }
      }
    } catch (err) {
      console.error('Delete history failed: ' + JSON.stringify(err))
      promptAction.showToast({ message: '删除失败' })
    }
  }

  async clearAllHistory() {
    try {
      let httpRequest = http.createHttp()
      let url = 'http://10.0.2.2:8000/api/history/clear'
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.DELETE,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      })

      if (response.responseCode === 200) {
        promptAction.showToast({ message: '清空成功' })
        this.historyList = []
        this.totalCount = 0
      }
    } catch (err) {
      console.error('Clear history failed: ' + JSON.stringify(err))
      promptAction.showToast({ message: '清空失败' })
    }
  }

  showDeleteConfirm(id: number) {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: '确定要删除这条历史记录吗？',
      buttons: [
        { text: '取消', color: '#909399' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }, (err, data) => {
      if (!err && data.index === 1) {
        this.deleteHistoryItem(id)
      }
    })
  }

  showClearConfirm() {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认清空',
      message: '确定要清空所有历史记录吗？此操作不可恢复。',
      buttons: [
        { text: '取消', color: '#909399' },
        { text: '清空', color: '#FF4D4F' }
      ]
    }, (err, data) => {
      if (!err && data.index === 1) {
        this.clearAllHistory()
      }
    })
  }

  showDetail(item: HistoryItem) {
    this.getUIContext().getPromptAction().showDialog({
      title: '题目详情',
      message: `题目:\n${item.question}\n\n答案:\n${item.answer}`,
      buttons: [{ text: '关闭', color: '#000000' }]
    })
  }
}

@Builder
export function HistoryBuilder() {
  History();
}
