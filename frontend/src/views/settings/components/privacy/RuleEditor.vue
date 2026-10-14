<script setup lang="ts">
import type { PrivacyRule, PrivacySample } from '@/api/modules/settings/privacy'
import { ZButton, ZCheckbox, ZDialog, ZForm, ZFormItem, ZIconButton, ZInput, ZPopover, ZSelect, ZTextarea } from '@codex-proxy/ui'
import { ArrowDown, ArrowUp, CircleHelp, Play, Plus, Trash2 } from '@lucide/vue'
import { cloneDeep } from 'es-toolkit'
import { computed, ref, shallowRef, useId, watch } from 'vue'
import { usePrivacyPreview } from '../../composables/usePrivacyPreview'
import { actions, exampleRequest, fieldsByScope, newRule, newStep, scopes } from './presets'

const props = defineProps<{ rule: PrivacyRule | null, maxSteps: number, isNew: boolean, disabled: boolean }>()
const emit = defineEmits<{ apply: [rule: PrivacyRule] }>()
const open = defineModel<boolean>({ required: true })
const fieldPresetId = useId()
const draft = ref<PrivacyRule>(newRule())
const selectedIndex = shallowRef(0)
const step = computed(() => draft.value.steps[selectedIndex.value]!)
const stepOptions = computed(() => draft.value.steps.map((step, index) => ({ value: index, label: `${index + 1} · ${fieldsByScope[step.scope]?.find(field => field.value === step.selector)?.label || step.selector}` })))
const sample = shallowRef('')
const fixedValues = ref<string[]>(['""'])
const fixedValue = computed({ get: () => fixedValues.value[selectedIndex.value] ?? '""', set: (value: string) => {
  fixedValues.value[selectedIndex.value] = value
} })
const localError = shallowRef('')
const preview = usePrivacyPreview()
const { loading, error, result } = preview
const usesPattern = computed(() => ['regex_replace', 'rename_key'].includes(step.value.action) || (step.value.action === 'remove_field' && step.value.pattern !== null))
const pattern = computed({ get: () => step.value.pattern ?? '', set: (value: string) => {
  step.value.pattern = value
} })
const conditional = computed({ get: () => step.value.pattern !== null, set: (value: boolean) => {
  step.value.pattern = value ? '' : null
} })
const fields = computed(() => fieldsByScope[step.value.scope] ?? [])
const fieldChoice = computed({ get: () => fields.value.some(field => field.value === step.value.selector) ? step.value.selector : '', set: (value: string) => {
  step.value.selector = value
} })
const selectorPlaceholder = computed(() => ({
  turn_metadata: '例如：$.workspaces.*.associated_remote_urls.*',
  desktop_git_context: '例如：$.remotes[*].fetchUrl',
  environment_text: '填写 $，匹配整段环境文本',
  request_body: '例如：$.metadata.workspace',
  request_header: '例如：x-client-name',
})[step.value.scope])
const processed = computed(() => result.value ? JSON.stringify({ body: result.value.body, headers: result.value.headers, turnMetadata: result.value.turnMetadata }, null, 2) : '')
const outcome = computed(() => result.value?.outcomes[0])

watch(open, (value) => {
  preview.invalidate()
  localError.value = ''
  if (value) {
    selectedIndex.value = 0
    draft.value = cloneDeep(props.rule ?? newRule())
    fixedValues.value = draft.value.steps.map(step => JSON.stringify(step.value))
    sample.value = JSON.stringify(exampleRequest(), null, 2)
  }
  else {
    sample.value = ''
  }
})
watch(() => step.value.action, (action) => {
  if (action === 'set_value')
    step.value.pattern = null
  else if (action !== 'remove_field' && step.value.pattern === null)
    step.value.pattern = ''
})
watch([draft, sample, fixedValues], () => {
  preview.invalidate()
  localError.value = ''
}, { deep: true, flush: 'sync' })

function addStep() {
  if (draft.value.steps.length >= props.maxSteps)
    return
  draft.value.steps.push(newStep())
  fixedValues.value.push('""')
  selectedIndex.value = draft.value.steps.length - 1
}
function removeStep() {
  if (draft.value.steps.length <= 1)
    return
  const index = selectedIndex.value
  selectedIndex.value = Math.max(0, index - 1)
  draft.value.steps.splice(index, 1)
  fixedValues.value.splice(index, 1)
}
function moveStep(offset: number) {
  const index = selectedIndex.value
  const target = index + offset
  if (!draft.value.steps[target])
    return
  const [moved] = draft.value.steps.splice(index, 1)
  draft.value.steps.splice(target, 0, moved!)
  const [fixed] = fixedValues.value.splice(index, 1)
  fixedValues.value.splice(target, 0, fixed!)
  selectedIndex.value = target
}
function preparedRule() {
  const rule = cloneDeep(draft.value)
  if (!rule.name.trim())
    throw new Error('请填写规则名称')
  if (rule.steps.length > props.maxSteps)
    throw new Error('所有规则合计最多 32 个处理步骤')
  rule.steps.forEach((step, index) => {
    if (!step.selector.trim())
      throw new Error(`请填写步骤 ${index + 1} 的字段路径`)
    if (step.action === 'set_value') {
      try {
        step.value = JSON.parse(fixedValues.value[index] ?? '""')
      }
      catch { throw new Error(`步骤 ${index + 1} 的固定值应为 JSON，例如 "别名"、false 或 123`) }
    }
  })
  return rule
}
async function test() {
  try {
    const rule = preparedRule()
    const value: PrivacySample = JSON.parse(sample.value)
    await preview.run({ enabled: true, onError: 'skip_rule', rules: [{ ...rule, enabled: true }] }, value)
  }
  catch (cause) { localError.value = cause instanceof Error ? cause.message : '样本格式无效' }
}
async function apply() {
  if (props.disabled)
    return
  try {
    const rule = preparedRule()
    const validated = await preview.run({ enabled: false, onError: 'skip_rule', rules: [rule] }, { body: {}, headers: {}, turnMetadata: null })
    if (!validated || !open.value)
      return
    emit('apply', rule)
    open.value = false
  }
  catch (cause) { localError.value = cause instanceof Error ? cause.message : '规则格式无效' }
}
</script>

<template>
  <ZDialog v-model="open" :title="isNew ? '添加规则' : '编辑规则'" width="48rem">
    <div class="grid gap-4">
      <ZForm class="sm:grid-cols-2">
        <ZFormItem class="sm:col-span-2" label="规则名称" required>
          <ZInput v-model="draft.name" placeholder="例如：统一工作区信息" aria-label="规则名称" maxlength="64" />
        </ZFormItem>
        <ZFormItem class="sm:col-span-2" label="处理步骤">
          <template #label-extra>
            <ZPopover trigger="hover-click">
              <template #reference="{ open: helpOpen }">
                <ZIconButton size="small" aria-label="处理步骤说明" :title="undefined" class="-my-2 hover:bg-transparent! active:bg-transparent!" :aria-expanded="helpOpen">
                  <CircleHelp class="size-3.5" />
                </ZIconButton>
              </template>
              <div class="max-w-72 space-y-2 p-3 text-cp-sm text-cp-text-secondary">
                <p class="m-0">
                  处理步骤是一条规则内的具体操作，每一步可分别设置作用范围、字段和处理方式
                </p>
                <p class="m-0">
                  步骤按编号依次执行，后一步基于前一步的结果处理，例如先统一用户名，再统一工作区路径
                </p>
                <p class="m-0">
                  所有步骤共用规则开关，任一步骤失败会撤销本条规则的全部修改，再按失败策略跳过或阻止请求
                </p>
              </div>
            </ZPopover>
          </template>
          <div class="flex items-center gap-2">
            <ZSelect v-model="selectedIndex" class="min-w-0 flex-1" :options="stepOptions" aria-label="选择处理步骤" />
            <ZIconButton :disabled="selectedIndex === 0" aria-label="上移步骤" @click="moveStep(-1)">
              <ArrowUp class="size-4" />
            </ZIconButton>
            <ZIconButton :disabled="selectedIndex === draft.steps.length - 1" aria-label="下移步骤" @click="moveStep(1)">
              <ArrowDown class="size-4" />
            </ZIconButton>
            <ZIconButton :disabled="draft.steps.length >= maxSteps" aria-label="添加步骤" @click="addStep">
              <Plus class="size-4" />
            </ZIconButton>
            <ZIconButton :disabled="draft.steps.length === 1" aria-label="删除步骤" @click="removeStep">
              <Trash2 class="size-4" />
            </ZIconButton>
          </div>
        </ZFormItem>
        <ZFormItem label="作用范围">
          <ZSelect v-model="step.scope" class="w-full" :options="scopes" aria-label="作用范围" />
        </ZFormItem>
        <ZFormItem label="处理方式">
          <ZSelect v-model="step.action" class="w-full" :options="actions" aria-label="处理方式" />
        </ZFormItem>
        <ZFormItem class="sm:col-span-2" :label="step.scope === 'request_header' ? '请求头名称' : '字段路径'" required>
          <template #label-extra>
            <ZPopover trigger="hover-click">
              <template #reference="{ open: helpOpen }">
                <ZIconButton size="small" aria-label="字段路径语法" :title="undefined" class="-my-2 hover:bg-transparent! active:bg-transparent!" :aria-expanded="helpOpen">
                  <CircleHelp class="size-3.5" />
                </ZIconButton>
              </template>
              <div class="max-w-72 p-3 text-cp-sm text-cp-text-secondary">
                支持对象成员、双引号键名、数组索引和 * 通配，例如 $["workspaces"]["/home/alex/demo"]<br>环境文本使用 $，请求头直接填写名称
              </div>
            </ZPopover>
          </template>
          <div class="flex flex-wrap items-center gap-2 sm:flex-nowrap">
            <ZInput v-model="step.selector" :placeholder="selectorPlaceholder" aria-label="字段路径" maxlength="1024" class="min-w-0 flex-1 font-mono" :class="fields.length ? 'basis-full sm:basis-auto' : undefined" spellcheck="false" />
            <ZSelect v-if="fields.length" :id="fieldPresetId" v-model="fieldChoice" class="min-w-0 flex-1 sm:w-40 sm:flex-none" :options="fields" aria-label="常用字段" />
          </div>
        </ZFormItem>
        <ZCheckbox v-if="step.action === 'remove_field'" v-model="conditional" class="sm:col-span-2" label="仅删除值匹配正则的字段或数组项" />
        <ZFormItem v-if="usesPattern" :class="step.action === 'remove_field' ? 'sm:col-span-2' : undefined" label="匹配表达式">
          <ZInput v-model="pattern" :placeholder="step.action === 'rename_key' ? '例如：^/home/[^/]+/' : '例如：private-org'" aria-label="匹配表达式" maxlength="4096" spellcheck="false" class="font-mono" />
        </ZFormItem>
        <ZFormItem v-if="step.action === 'regex_replace' || step.action === 'rename_key'" label="替换内容">
          <template #label-extra>
            <ZPopover trigger="hover-click">
              <template #reference="{ open: helpOpen }">
                <ZIconButton size="small" aria-label="正则语法说明" :title="undefined" class="-my-2 hover:bg-transparent! active:bg-transparent!" :aria-expanded="helpOpen">
                  <CircleHelp class="size-3.5" />
                </ZIconButton>
              </template>
              <div class="max-w-72 p-3 text-cp-sm text-cp-text-secondary">
                ${1} 或 ${name} 引用捕获组，$$ 表示字面 $<br>使用 Rust regex 语法，不支持前后顾和模式中的反向引用
              </div>
            </ZPopover>
          </template>
          <ZInput v-model="step.replacement" :placeholder="step.action === 'rename_key' ? '例如：/home/user/' : '例如：team，留空则清除匹配内容'" aria-label="替换内容" maxlength="4096" spellcheck="false" class="font-mono" />
        </ZFormItem>
        <ZFormItem v-if="step.action === 'set_value'" class="sm:col-span-2" label="固定值（JSON）">
          <ZTextarea v-model="fixedValue" placeholder="例如：&quot;匿名&quot;、null 或 {}" :rows="2" maxlength="4096" aria-label="固定值 JSON" class="font-mono" />
        </ZFormItem>
        <div v-if="usesPattern" class="flex flex-wrap gap-x-4 gap-y-2 sm:col-span-2">
          <ZCheckbox v-if="step.action !== 'remove_field'" v-model="step.replaceAll" label="替换全部匹配" />
          <ZCheckbox v-model="step.caseInsensitive" label="忽略大小写" />
          <ZCheckbox v-model="step.multiLine" label="多行匹配" />
        </div>
      </ZForm>
      <section class="grid gap-2.5" aria-label="测试预览">
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-cp-sm font-emphasis">
            规则预览
          </h3>
          <div class="flex items-center gap-2">
            <span v-if="outcome" class="text-cp-xs text-cp-text-quaternary">{{ outcome.status === 'skipped' ? '规则已跳过' : `命中 ${outcome.matches} 处` }}</span>
            <ZButton size="small" variant="text" :loading="loading" aria-label="测试本条规则" @click="test">
              <template #icon>
                <Play class="size-3.5" />
              </template>测试
            </ZButton>
          </div>
        </div>
        <div class="grid min-w-0 gap-3 sm:grid-cols-2">
          <ZFormItem label="测试样本">
            <ZTextarea v-model="sample" size="small" resize="none" placeholder="粘贴包含 body、headers、turnMetadata 的请求样本" maxlength="262144" aria-label="测试样本" class="font-mono [&_textarea]:block [&_textarea]:h-36" spellcheck="false" />
          </ZFormItem>
          <div class="grid min-w-0 content-start gap-2">
            <span class="flex min-h-4 items-center text-cp leading-none font-medium text-cp-text-secondary">处理后</span>
            <pre class="cp-scrollbar m-0 h-36 overflow-auto rounded-cp bg-cp-fill-quaternary p-3 font-mono text-cp-xs break-all whitespace-pre-wrap" data-preview-output>{{ processed || '点击测试查看结果' }}</pre>
          </div>
        </div>
        <p v-if="localError || error || outcome?.reason" role="alert" class="m-0 text-cp-sm text-cp-error-text">
          {{ localError || error || outcome?.reason }}
        </p>
      </section>
    </div>
    <template #footer>
      <ZButton @click="open = false">
        取消
      </ZButton>
      <ZButton type="primary" :loading="loading" :disabled="disabled" @click="apply">
        应用到草稿
      </ZButton>
    </template>
  </ZDialog>
</template>
