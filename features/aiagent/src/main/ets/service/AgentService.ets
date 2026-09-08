/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AiService } from './AiService';
import {
  AgentToolRegistry,
  ToolErrorResult,
  buildToolCallsMessage,
  buildToolDefinitions,
  buildToolResultMessage,
  getToolStepLabel,
} from './AgentTools';
import { AiMessage, AiResponseResult, AiToolCall } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const MAX_AGENT_ROUNDS = 5;
/** Tool-call rounds only need a small budget; the final answer gets the full one. */
const TOOL_ROUND_MAX_TOKENS = 1024;
/** Hard cap for the whole agent run so the UI can never spin forever. */
const AGENT_TOTAL_TIMEOUT_MS = 120000;

/** Thrown when the agent loop exceeds MAX_AGENT_ROUNDS; message is user-facing. */
export class AgentLimitError extends Error {
  constructor() {
    super('任务步骤过多，请换一种更具体的问法再试一次。');
  }
}

/** Thrown when the whole agent run exceeds AGENT_TOTAL_TIMEOUT_MS. */
export class AgentTimeoutError extends Error {
  constructor() {
    super('分析超时了，请稍后重试。');
  }
}

/**
 * ReAct-style agent loop for the AI tutor.
 *
 * 1. Send the conversation (plus tool definitions) to the LLM.
 * 2. If the model returns tool calls, execute them locally (each tool at most
 *    once per run) and feed the results back as tool messages, then loop.
 * 3. Once the model returns plain content, stream the final answer; if
 *    streaming fails or yields nothing, fall back to a non-streaming call.
 */
export class AgentService {
  private aiService: AiService = new AiService();
  private toolRegistry: AgentToolRegistry = new AgentToolRegistry();
  private executedTools: Set<string> = new Set();

  async run(
    messages: AiMessage[],
    onStep: (stepText: string, isDone: boolean) => void,
    onChunk: (chunk: string) => void,
  ): Promise<void> {
    const timeoutPromise = new Promise<void>((resolve, reject) => {
      setTimeout(() => {
        reject(new AgentTimeoutError());
      }, AGENT_TOTAL_TIMEOUT_MS);
    });

    try {
      await Promise.race([this.runInternal(messages, onStep, onChunk), timeoutPromise]);
    } catch (err) {
      if (err instanceof AgentTimeoutError) {
        this.cancel();
        throw err;
      }
      if (err instanceof AgentLimitError) {
        throw err;
      }
      throw err instanceof Error ? err : new Error('Unknown agent error');
    }
  }

  cancel(): void {
    this.aiService.cancelRequest();
  }

  private async runInternal(
    messages: AiMessage[],
    onStep: (stepText: string, isDone: boolean) => void,
    onChunk: (chunk: string) => void,
  ): Promise<void> {
    const working = this.copyMessages(messages);
    this.executedTools.clear();

    for (let round = 0; round < MAX_AGENT_ROUNDS; round++) {
      let result: AiResponseResult;
      try {
        result = await this.aiService.chat(working, buildToolDefinitions(), TOOL_ROUND_MAX_TOKENS);
      } catch (err) {
        const cause = err instanceof Error ? err : new Error('Agent tool call failed');
        if (round === 0) {
          // The tools call may fail if the API rejects function calling.
          // Fall back to a plain (non-streaming) conversation so the tutor
          // always remains usable even when streaming or tools are broken.
          Logger.error(`Agent tool call failed, falling back to plain chat: ${cause.message}`);
          const plain = await this.aiService.chat(working);
          if (plain.content.length > 0) {
            onChunk(plain.content);
            return;
          }
        }
        throw cause;
      }

      Logger.info(`[Agent] round ${round}: ${result.toolCalls.length} tool calls, ${result.content.length} content chars`);
      if (result.toolCalls.length > 0) {
        await this.applyToolCalls(working, result, onStep);
        continue;
      }

      await this.deliverFinalAnswer(working, onChunk);
      return;
    }

    Logger.error('Agent loop exceeded max rounds');
    throw new AgentLimitError();
  }

  /**
   * Delivers the final answer. Streaming is preferred, but when it fails or
   * yields nothing (some HarmonyOS http configurations never fire
   * dataReceive), the shared fallback path in AiService switches to a plain
   * non-streaming call so the user always gets a reply.
   */
  private async deliverFinalAnswer(working: AiMessage[], onChunk: (chunk: string) => void): Promise<void> {
    const delivered = await this.aiService.chatWithFallback(working, onChunk);
    if (delivered === 0) {
      throw new Error('AI 未返回有效回答，请稍后重试。');
    }
  }

  private async applyToolCalls(
    messages: AiMessage[],
    result: AiResponseResult,
    onStep: (stepText: string, isDone: boolean) => void,
  ): Promise<void> {
    messages.push(buildToolCallsMessage(result.toolCalls));

    for (let i = 0; i < result.toolCalls.length; i++) {
      const call: AiToolCall = result.toolCalls[i];
      const toolName = call.function.name;
      const stepLabel = getToolStepLabel(toolName);
      onStep(stepLabel, false);

      let toolResult: string;
      if (this.executedTools.has(toolName)) {
        // Force convergence: never run the same tool twice in one agent run.
        const dedupe = new ToolErrorResult();
        dedupe.error = `工具 ${toolName} 已执行过，请基于已有数据直接作答，不要再调用工具。`;
        toolResult = JSON.stringify(dedupe);
      } else {
        this.executedTools.add(toolName);
        try {
          toolResult = await this.toolRegistry.execute(toolName, call.function.arguments);
        } catch (err) {
          const errMsg = err instanceof Error ? err.message : 'Unknown error';
          Logger.error(`Tool ${toolName} failed: ${errMsg}`);
          const toolError = new ToolErrorResult();
          toolError.error = `工具 ${toolName} 执行失败：${errMsg}`;
          toolResult = JSON.stringify(toolError);
        }
      }
      Logger.info(`[Agent] tool ${toolName} result: ${toolResult.length} chars`);
      messages.push(buildToolResultMessage(call.id, toolResult));
      onStep(stepLabel, true);
    }
  }

  private copyMessages(source: AiMessage[]): AiMessage[] {
    const copied: AiMessage[] = [];
    for (const message of source) {
      const clone = new AiMessage();
      clone.role = message.role;
      clone.content = message.content;
      clone.tool_call_id = message.tool_call_id;
      clone.tool_calls = message.tool_calls;
      copied.push(clone);
    }
    return copied;
  }
}
