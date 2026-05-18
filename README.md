# 教育类行业实践

## 简介

本设计为教育类HarmonyOS应用架构设计实践，提供教育类应用常见的图文学习、音视频学习、考试等功能。

## 效果预览

<img src="./screenshots/Education_Framework_Code_V1.webp" width=200>

## 约束与限制

- 本示例支持API Version 20 Release及以上版本。
- 本示例支持HarmonyOS 6.0.0 Release SDK及以上版本。
- 本示例需要使用DevEco Studio 6.0.0 Release及以上版本进行编译运行。

## 使用说明

- 首页采用各类APP常用的页面导航布局，底部通过Tabs组件设置导航样式 。
- 行业特色功能页面，如：课程展示、课程学习、学习进度跟踪、考试练习等。
- 课程展示：根据不同的分类，通过列表、宫格的形式展示可学习的课程。
- 课程学习：查看课程相关的内容，包含图文课程或音视频课程。
- 考试练习：提供题目进行在线考试，包含考试时间等。

## 实现思路

* 视频播放代码实现

  ```
  createAVPlayer() {
    media.createAVPlayer().then((video: media.AVPlayer) => {
      if (video != null) {
        this.avPlayer = video;
        this.setAVPlayerCallback(this.avPlayer);
        if (this.avPlayer) {
          // 当前链接为参考链接
          this.avPlayer.url =
            `https://www-file.huawei.com/-/media/corporate/minisite/hc2024/v4/videos/highlights/huawei-connect-2024-summary-cn-1080p.mp4`; // 示例，参考链接
        }
      } else {
      }
    }).catch((error: BusinessError) => {
    });
  }
  ```

* 在线考试代码实现

  ```
  // 代码文件 mine/src/ets/pages/MineStartTestPage.ets
  TextTimer({ isCountDown: true, count: this.count, controller: this.textTimerController })
    .format(this.format)
    .fontColor(Color.Black)
    .fontSize(30)
    .onTimer((utc: number, elapsedTime: number) => {
      this.elapsedTime = this.count - elapsedTime * 1000;
      if (elapsedTime * 1000 === this.count) {
        // 倒计时结束
        this.submit(true);
      }
    })
    .onAppear(() => {
      this.textTimerController.start();
    })
    .onDisAppear(() => {
      // 页面切换，保存当前的值
      if (!this.isSubmitted) {
        AppStorage.setOrCreate('MyCount', this.elapsedTime);
      } else {
        AppStorage.setOrCreate('Score', 0);
      }
    });
  ```

* 考试时间结束会自动交卷等逻辑操作：

  ```
    // 代码文件 mine/src/ets/pages/MineStartTestPage.ets
    submit(force: Boolean): void {
      if (force) {
        this.isSubmitted = true;
        this.pathStack.pushPathByName('MineTestResPage', null);
        for (let i = 1; i <= this.questionData.length; i++) {
          if (this.getValueByKey(i.toString()) === this.questionData[i-1].rightQues) {
            this.score += 10;
          }
        }
        for (let i = 0; i < ERROR_MODELS.length; i++) {
          ERROR_MODELS[i].answer = 0;
        }
        this.textTimerController.reset();
        AppStorage.setOrCreate('MyCount', 0);
        AppStorage.setOrCreate('Score', this.score);
        AppStorage.setOrCreate('Time', EXAM_DURATION);
      } else {
        if (this.currentIndex >= ERROR_MODELS.length - 1) {
          this.tjDialog.open();
          return;
        }
        this.currentIndex += 1;
        this.currentModel = ERROR_MODELS[this.currentIndex];
      }
    }
  ```

## 工程目录

```
├──common/basic/src/main/ets                          // 公共模块
│  ├──constants
│  │  ├──CommonConstants.ets                          // 公共样式
│  │  └──StyleConstants.ets                           // 常用宽高样式
│  ├──resources
│  │  └──ResManager.ets                               // 公共模块导出资源
│  └──utils
│     ├──BreakpointUtil.ets 
│     ├──Logger.ets  
│     ├──MyGlobalContext.ets  
│     └──PreferencesUtil.ets     
├──entry/src/main/ets                                 // 主页面
│  ├──entryability
│  │  └──EntryAbility.ets                             // 程序入口
│  ├──pages
│  │  ├──Index.ets                                    // 首页配置tabBar
│  │  └──Tab.ets                                      // 自定义tab页
│  └──viewmodel
│     └──ConstantsInterface.ets
├──features
│  ├──home/src/main/ets                               // 首页
│  │  ├──secondary                                    // 二级跳转页面
│  │  │  ├──HomePage.ets                              // 首页组件
│  │  │  └──JumpPage.ets                              // 模板列表页
│  │  ├──utils
│  │  │  └──Calc.ets 
│  │  └──views
│  │     ├──BreakpointUtil.ets      
│  │     ├──CommonConstants.ets
│  │     ├──HomeView.ets      
│  │     ├──HomeViewModel.ets                         // 首页数据模型
│  │     └──SecondView.ets       
│  ├──login/src/main/ets                               
│  │  ├──common
│  │  │  ├──constants   
│  │  │  │  └──AccountConstants.ets                 
│  │  │  └──resources  
│  │  │     └──ResManager.ets                    
│  │  ├──constants
│  │  │  └──StyleConstants.ets 
│  │  ├──dialog
│  │  │  └──DistrictTownDialog.ets 
│  │  ├──viewmodel
│  │  │  ├──AccountInfo.ets 
│  │  │  └──ConstantsInterface.ets
│  │  └──views
│  │     ├──LoginView.ets      
│  │     ├──LogoutNextView.ets
│  │     ├──LogoutView.ets      
│  │     ├──ModifyPasswordView.ets                         
│  │     ├──PolicyAgreement.ets    
│  │     └──RegisterView.ets 
│  ├──mine/src/main/ets                               // 我的
│  │  ├──utils
│  │  │  └──Calc.ets   
│  │  ├──viewmodel
│  │  │  ├──MineCourseListModel.ets                   // 我的课程模型
│  │  │  ├──MineErrorModel.ets                        // 我的错题模型
│  │  │  ├──MineListModel.ets                         // 我的页面模型
│  │  │  ├──MineLocalData.ets                         // 我的本地数据
│  │  │  ├──MineOnlineTestModel.ets                   // 考试模型
│  │  │  └──MineSetListModel.ets                      // 设置数据模型
│  │  └──views
│  │     ├──LogoutDialog.ets                          // 退出登录 弹窗
│  │     ├──MineCoursePage.ets                        // 课程
│  │     ├──MineErrorPage.ets                         // 错题
│  │     ├──MineModiPersonPage.ets
│  │     ├──MineOnlineTestPage.ets
│  │     ├──MinePage.ets                              // 我的tab页
│  │     ├──MineSetPage.ets                           // 设置页面
│  │     ├──MineStartTestPage.ets
│  │     ├──MineTestResPage.ets
│  │     └──MineTrainPage.ets                         // 培训
│  ├──online/src/main/ets                             // 消息
│  │  ├──utils
│  │  │  └──Calc.ets
│  │  ├──viewmodel
│  │  │  ├──OnlineListModel.ets                       // 消息模型类
│  │  │  └──OnlineLocalData.ets                       // 消息本地数据
│  │  └──views
│  │     └──OnlineIndexView.ets          
│  └──train/src/main/ets                              // 培训
│     ├──common
│     │  └──constants           
│     │       └──TrainConstants.ets
│     ├──pages
│     │  ├──CourseDetailPage.ets                      // 课程详情
│     │  ├──ExaminationDetailPage.ets                 // 考试页面
│     │  ├──Index.ets                                 // 培训首页
│     │  └──TrainDetailPage.ets                       // 培训详情
│     ├──utils
│     │  └──Calc.ets
│     ├──view
│     │  ├──AVPlayerDemo.ets                          // 播放组件
│     │  ├──Course.ets                                // 课程组件
│     │  ├──CourseEvaluate.ets                        // 评价组件
│     │  ├──CourseIntroduce.ets                       // 介绍组件
│     │  ├──CourseList.ets                            // 课程列表组件
│     │  ├──Empty.ets                                 // 无数据组件
│     │  ├──Examination.ets
│     │  ├──Introduction.ets
│     │  └──TrainListPage.ets                         // 培训列表组件
│     └──viewmodel
│        ├──ExaminationInfoModel.ets                  // 考试本地数据
│        ├──NavInfoModel.ets                          // 导航传参
│        └──TrainInfoModel.ets                        // 培训数据
└──entry/src/main/resources                           // 资源文件目录
```
