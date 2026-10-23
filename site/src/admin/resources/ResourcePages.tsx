import { useEffect, useState, useMemo } from "react";
import {
  Link,
  useNavigate,
  useLocation,
  useSearchParams,
} from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
  type VisibilityState,
} from "@tanstack/react-table";
import { useForm, Controller } from "react-hook-form";
import { toast } from "sonner";
import {
  ArrowUpDown,
  Copy,
  Columns3,
  Plus,
  Download,
  RefreshCw,
  Save,
  Trash2,
} from "lucide-react";
import {
  Button,
  Dialog,
  Badge,
  PageHeader,
  ErrorState,
  Loading,
  Empty,
} from "../components/ui";
import {
  useAdmin,
  useAction,
  queryClient,
  reportError,
} from "../providers/context";
import { dataProvider } from "../providers/dataProvider";
import type {
  ResourceConfig,
  FormFieldConfig,
  RowActionConfig,
} from "./config";
import { resourceConfigs } from "./config";
import {
  valueAt,
  valueLabel,
  initialValue,
  actionConfirmation,
} from "./helpers";
export { actionConfirmation } from "./helpers";
type RecordData = Record<string, any>;
const detailActions: Record<string, string> = {
  posts: "getPost",
  polls: "getPoll",
  profiles: "getProfile",
  reports: "getModerationReport",
};
const scopedCreate = new Set([
  "teachers",
  "courses",
  "dishes",
  "community-banners",
]);
const dated = new Set([
  "posts",
  "polls",
  "comments",
  "reports",
  "profiles",
  "feedback",
  "postgraduate-suggestions",
  "suggestions",
  "ratings",
  "audit-logs",
]);
export function ResourceList({
  resource,
  config,
}: {
  resource: string;
  config: ResourceConfig;
}) {
  const { campus, setCampus, identity, can } = useAdmin(),
    navigate = useNavigate(),
    location = useLocation(),
    [params, setParams] = useSearchParams();
  const filters = useMemo<RecordData>(() => {
    try {
      return (
        JSON.parse(params.get("filter") ?? "null") ??
        config.defaultFilters ??
        {}
      );
    } catch {
      return config.defaultFilters ?? {};
    }
  }, [params, config]);
  const page = Math.max(1, Number(params.get("page")) || 1),
    perPage = [20, 50, 100].includes(Number(params.get("perPage")))
      ? Number(params.get("perPage"))
      : 20,
    sortField = params.get("sort") ?? config.defaultSort?.field ?? "created_at",
    sortOrder = params.get("order") ?? config.defaultSort?.order ?? "DESC";
  const selectedID = location.pathname.slice(resource.length + 2),
    [edit, setEdit] = useState<RecordData | null>(null),
    [action, setAction] = useState<{
      record: RecordData;
      definition: RowActionConfig;
    } | null>(null),
    [columnsOpen, setColumnsOpen] = useState(false),
    [viewsOpen, setViewsOpen] = useState(false),
    [viewName, setViewName] = useState(""),
    [visibility, setVisibility] = useState<VisibilityState>({}),
    [selection, setSelection] = useState<Record<string, boolean>>({}),
    [bulk, setBulk] = useState(false),
    [bulkStatus, setBulkStatus] = useState("hidden");
  const viewsKey = `leafy-admin-views:${identity?.admin.id}:${resource}`;
  const [views, setViews] = useState<
    {
      name: string;
      campus: string;
      query: string;
      visibility: VisibilityState;
    }[]
  >(() => {
    try {
      return JSON.parse(localStorage.getItem(viewsKey) ?? "[]");
    } catch {
      return [];
    }
  });
  const query = useQuery({
    queryKey: [
      "admin",
      identity?.admin.id,
      campus,
      resource,
      filters,
      page,
      perPage,
      sortField,
      sortOrder,
    ],
    queryFn: ({ signal }) =>
      dataProvider.getList(resource, {
        filter: {
          ...filters,
          campusID: campus === "all" ? undefined : campus,
          timezone: "Asia/Shanghai",
        },
        pagination: { page, perPage },
        sort: { field: sortField, order: sortOrder },
        signal,
      }),
  });
  useEffect(() => setSelection({}), [campus, params]);
  const update = (values: Record<string, unknown>) => {
    const next = new URLSearchParams(params);
    Object.entries(values).forEach(([key, value]) =>
      value == null ? next.delete(key) : next.set(key, String(value)),
    );
    setParams(next);
  };
  const filter = (key: string, value: unknown) =>
    update({ filter: JSON.stringify({ ...filters, [key]: value }), page: 1 });
  const refresh = () =>
    void queryClient.invalidateQueries({ queryKey: ["admin"] });
  const rows = query.data?.data ?? [],
    canBulk = ["posts", "comments"].includes(resource) && can(resource, "bulk");
  const displayColumns = config.columns.filter(
    (c) =>
      resource !== "profiles" ||
      identity?.admin.role === "super_admin" ||
      c.source !== "edu_id",
  );
  const definitions = useMemo<ColumnDef<RecordData>[]>(
    () => [
      ...(canBulk
        ? [
            {
              id: "select",
              header: ({ table }: any) => (
                <input
                  type="checkbox"
                  aria-label="选择本页"
                  checked={table.getIsAllRowsSelected()}
                  onChange={table.getToggleAllRowsSelectedHandler()}
                />
              ),
              cell: ({ row }: any) => (
                <input
                  type="checkbox"
                  aria-label={`选择 ${row.original.id}`}
                  checked={row.getIsSelected()}
                  onChange={row.getToggleSelectedHandler()}
                />
              ),
            },
          ]
        : []),
      ...displayColumns.map((column, index) => ({
        id: column.source,
        accessorFn: (r: RecordData) => valueAt(r, column.source),
        header: () =>
          column.sortable ? (
            <button
              onClick={() =>
                update({
                  sort: column.source,
                  order:
                    sortField === column.source && sortOrder === "DESC"
                      ? "ASC"
                      : "DESC",
                  page: 1,
                })
              }
            >
              {column.label}
              <ArrowUpDown size={12} />
            </button>
          ) : (
            column.label
          ),
        cell: ({ row, getValue }: any) => {
          const value = getValue();
          if (column.kind === "image")
            return value ? (
              <img
                src={String(value)}
                alt={column.label}
                style={{ width: 96, height: 36, objectFit: "cover" }}
              />
            ) : (
              "—"
            );
          const text =
            column.kind === "date"
              ? dateLabel(value)
              : column.kind === "json"
                ? JSON.stringify(value)
                : valueLabel(value ?? column.fallback);
          return index === 0 ? (
            <Link
              to={`/${resource}/${encodeURIComponent(row.original.id)}`}
              title={text}
            >
              {text}
            </Link>
          ) : column.source === "status" ? (
            <Badge
              tone={
                value === "published"
                  ? "success"
                  : value === "hidden" || value === "failed"
                    ? "danger"
                    : "neutral"
              }
            >
              {resource === "polls" && value === "pending_review"
                ? "待审核"
                : text}
            </Badge>
          ) : (
            <span title={text}>{text}</span>
          );
        },
      })),
      {
        id: "actions",
        header: "操作",
        cell: ({ row }: any) => {
          const r = row.original;
          return (
            <div className="studio-actions">
              <Link
                className="studio-button"
                to={`/${resource}/${encodeURIComponent(r.id)}`}
              >
                详情
              </Link>
              <Button
                variant="ghost"
                aria-label={`复制 ID ${r.id}`}
                onClick={() =>
                  void navigator.clipboard
                    .writeText(String(r.id))
                    .then(() => toast.success("ID 已复制"))
                    .catch(reportError)
                }
              >
                <Copy size={13} />
              </Button>
              {config.editable && config.editForm && can(resource, "edit") && (
                <Button onClick={() => setEdit(r)}>编辑</Button>
              )}
              {config.actions
                ?.filter(
                  (a) =>
                    (!a.visible || a.visible(r)) &&
                    can(resource, a.permissionAction ?? "edit"),
                )
                .map((a) => (
                  <Button
                    key={a.label}
                    variant={a.tone === "danger" ? "danger" : "default"}
                    onClick={() => setAction({ record: r, definition: a })}
                  >
                    {a.label}
                  </Button>
                ))}
            </div>
          );
        },
      },
    ],
    [config, canBulk, can, resource, sortField, sortOrder, params],
  );
  const table = useReactTable({
    data: rows,
    columns: definitions,
    getCoreRowModel: getCoreRowModel(),
    manualPagination: true,
    manualSorting: true,
    state: { columnVisibility: visibility, rowSelection: selection },
    onColumnVisibilityChange: setVisibility,
    onRowSelectionChange: setSelection,
    getRowId: (r) => String(r.id),
  });
  const filterFields: FormFieldConfig[] = [
    ...(config.searchable === false
      ? []
      : [{ source: "search", label: "搜索" }]),
    ...(config.statusChoices
      ? [
          {
            source: "status",
            label: "状态",
            kind: "select" as const,
            choices: config.statusChoices,
          },
        ]
      : []),
    ...(resource === "ratings"
      ? [
          {
            source: "target",
            label: "评分类型",
            kind: "select" as const,
            choices: [
              { id: "teacher", name: "教师" },
              { id: "course", name: "课程" },
              { id: "dish", name: "菜品" },
            ],
          },
        ]
      : []),
    ...(config.filters ?? []),
    ...(dated.has(resource)
      ? [
          { source: "start", label: "开始日期", kind: "date" as const },
          { source: "end", label: "结束日期", kind: "date" as const },
        ]
      : []),
  ];
  return (
    <>
      <PageHeader title={config.label} description="查看、筛选和管理业务记录">
        <div className="studio-actions">
          <Button aria-label="刷新" onClick={refresh}>
            <RefreshCw size={13} />
          </Button>
          {config.createForm && can(resource, "create") && (
            <Button
              variant="primary"
              disabled={scopedCreate.has(resource) && campus === "all"}
              onClick={() => setEdit({})}
            >
              <Plus size={13} />
              新增
            </Button>
          )}
        </div>
      </PageHeader>
      {["campuses", "campus-requests"].includes(resource) && (
        <div className="studio-tabs">
          <Link
            className={resource === "campuses" ? "active" : ""}
            to="/campuses"
          >
            学校空间
          </Link>
          <Link
            className={resource === "campus-requests" ? "active" : ""}
            to="/campus-requests"
          >
            学校申请
          </Link>
        </div>
      )}
      {["postgraduate", "postgraduate-suggestions"].includes(resource) && (
        <div className="studio-tabs">
          <Link
            className={resource === "postgraduate" ? "active" : ""}
            to="/postgraduate"
          >
            公开来源
          </Link>
          <Link
            className={resource === "postgraduate-suggestions" ? "active" : ""}
            to="/postgraduate-suggestions"
          >
            用户线索
          </Link>
        </div>
      )}
      <div className="studio-card">
        <div className="studio-toolbar">
          <div className="studio-filters">
            {filterFields.map((field) => (
              <label key={field.source}>
                {field.label}
                {field.kind === "select" ? (
                  <select
                    aria-label={field.label}
                    value={String(
                      filters[field.source] ?? field.choices?.[0]?.id ?? "all",
                    )}
                    onChange={(e) => {
                      const choice = field.choices?.find(
                        (c) => String(c.id) === e.target.value,
                      );
                      filter(field.source, choice?.id ?? e.target.value);
                    }}
                  >
                    {!field.choices?.some((c) => c.id === "all") &&
                      field.source !== "target" && (
                        <option value="all">全部</option>
                      )}
                    {field.choices?.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    aria-label={field.label}
                    type={field.kind === "date" ? "date" : "text"}
                    value={String(filters[field.source] ?? "")}
                    onChange={(e) => filter(field.source, e.target.value)}
                  />
                )}
              </label>
            ))}
            <Button
              variant="ghost"
              onClick={() =>
                update({ filter: JSON.stringify({ status: "all" }), page: 1 })
              }
            >
              清除筛选
            </Button>
          </div>
          <div className="studio-actions">
            <Button onClick={() => setViewsOpen(true)}>
              <Save size={13} />
              视图
            </Button>
            <Button onClick={() => setColumnsOpen(true)}>
              <Columns3 size={13} />列
            </Button>
            {config.exportable && can(resource, "export") && (
              <Button
                onClick={() =>
                  void dataProvider
                    .download({
                      resource,
                      filters: { ...filters, timezone: "Asia/Shanghai" },
                      sort: {
                        field: sortField,
                        order: sortOrder as "ASC" | "DESC",
                      },
                    })
                    .catch(reportError)
                }
              >
                <Download size={13} />
                导出 CSV
              </Button>
            )}
          </div>
        </div>
        {Object.values(selection).filter(Boolean).length > 0 && (
          <div className="studio-toolbar">
            <span>
              已选择 {Object.values(selection).filter(Boolean).length} 项
            </span>
            <div className="studio-actions">
              <select
                aria-label="批量状态"
                value={bulkStatus}
                onChange={(e) => setBulkStatus(e.target.value)}
              >
                <option value="hidden">批量下架</option>
                <option value="published">批量恢复</option>
              </select>
              <Button variant="danger" onClick={() => setBulk(true)}>
                执行批量操作
              </Button>
            </div>
          </div>
        )}
        {query.error ? (
          <ErrorState error={query.error} retry={() => void query.refetch()} />
        ) : query.isPending ? (
          <Loading />
        ) : rows.length === 0 ? (
          <Empty />
        ) : (
          <div className="studio-table-wrap">
            <table className="studio-table">
              <thead>
                {table.getHeaderGroups().map((group) => (
                  <tr key={group.id}>
                    {group.headers.map((header, index) => (
                      <th
                        key={header.id}
                        className={
                          index <= (canBulk ? 1 : 0) ? "sticky-col" : ""
                        }
                        style={
                          canBulk && index <= 1
                            ? {
                                left: index === 0 ? 0 : 48,
                                ...(index === 0
                                  ? { width: 48, minWidth: 48, maxWidth: 48 }
                                  : {}),
                              }
                            : undefined
                        }
                      >
                        {flexRender(
                          header.column.columnDef.header,
                          header.getContext(),
                        )}
                      </th>
                    ))}
                  </tr>
                ))}
              </thead>
              <tbody>
                {table.getRowModel().rows.map((row) => (
                  <tr key={row.id}>
                    {row.getVisibleCells().map((cell, index) => (
                      <td
                        key={cell.id}
                        className={
                          index <= (canBulk ? 1 : 0) ? "sticky-col" : ""
                        }
                        style={
                          canBulk && index <= 1
                            ? {
                                left: index === 0 ? 0 : 48,
                                ...(index === 0
                                  ? { width: 48, minWidth: 48, maxWidth: 48 }
                                  : {}),
                              }
                            : undefined
                        }
                      >
                        {flexRender(
                          cell.column.columnDef.cell,
                          cell.getContext(),
                        )}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="studio-pagination">
          <span>共 {query.data?.total ?? "—"} 条</span>
          <select
            aria-label="每页行数"
            value={perPage}
            onChange={(e) => update({ perPage: e.target.value, page: 1 })}
          >
            {[20, 50, 100].map((n) => (
              <option key={n} value={n}>
                {n} 条/页
              </option>
            ))}
          </select>
          <Button
            disabled={page <= 1}
            onClick={() => update({ page: page - 1 })}
          >
            上一页
          </Button>
          <span>
            {page} /{" "}
            {Math.max(1, Math.ceil((query.data?.total ?? 0) / perPage))}
          </span>
          <Button
            disabled={!query.data || page * perPage >= query.data.total}
            onClick={() => update({ page: page + 1 })}
          >
            下一页
          </Button>
        </div>
      </div>
      {selectedID && selectedID !== "create" && (
        <DetailSheet
          resource={resource}
          id={decodeURIComponent(selectedID)}
          record={rows.find(
            (r) => String(r.id) === decodeURIComponent(selectedID),
          )}
          onClose={() =>
            navigate({ pathname: `/${resource}`, search: location.search })
          }
        />
      )}
      <Dialog
        open={columnsOpen}
        onClose={() => setColumnsOpen(false)}
        title="显示列"
      >
        <div className="studio-form studio-label-list">
          {table
            .getAllLeafColumns()
            .filter((c) => !["actions", "select"].includes(c.id))
            .map((column) => (
              <label key={column.id}>
                <input
                  type="checkbox"
                  checked={column.getIsVisible()}
                  onChange={column.getToggleVisibilityHandler()}
                />
                {config.columns.find((c) => c.source === column.id)?.label}
              </label>
            ))}
        </div>
      </Dialog>
      <Dialog
        open={viewsOpen}
        onClose={() => setViewsOpen(false)}
        title="保存当前视图"
      >
        <div className="studio-form">
          <label>
            视图名称
            <input
              value={viewName}
              onChange={(e) => setViewName(e.target.value)}
              maxLength={60}
            />
          </label>
          <Button
            disabled={!viewName.trim()}
            onClick={() => {
              const next = [
                ...views.filter((v) => v.name !== viewName.trim()),
                {
                  name: viewName.trim(),
                  campus,
                  query: params.toString(),
                  visibility,
                },
              ];
              localStorage.setItem(viewsKey, JSON.stringify(next));
              setViews(next);
              setViewName("");
              toast.success("视图已保存");
            }}
          >
            保存视图
          </Button>
          {views.map((v) => (
            <div
              className="flex items-center justify-between gap-2"
              key={v.name}
            >
              <Button
                onClick={() => {
                  setCampus(v.campus);
                  setParams(v.query);
                  setVisibility(v.visibility);
                  setViewsOpen(false);
                }}
              >
                {v.name}
              </Button>
              <Button
                aria-label={`删除视图 ${v.name}`}
                onClick={() => {
                  const next = views.filter((x) => x.name !== v.name);
                  localStorage.setItem(viewsKey, JSON.stringify(next));
                  setViews(next);
                }}
              >
                <Trash2 size={13} />
              </Button>
            </div>
          ))}
        </div>
      </Dialog>
      {edit && (
        <RecordForm
          resource={resource}
          record={edit}
          fields={edit.id ? (config.editForm ?? []) : (config.createForm ?? [])}
          title={`${edit.id ? "编辑" : "新增"}${config.label}`}
          onClose={() => setEdit(null)}
        />
      )}{" "}
      {action && (
        <ActionForm
          resource={resource}
          record={action.record}
          action={action.definition}
          onClose={() => setAction(null)}
        />
      )}{" "}
      {bulk && (
        <ActionForm
          resource={resource}
          record={{
            id: "batch",
            title: `${Object.values(selection).filter(Boolean).length} 条记录`,
          }}
          action={{
            label: bulkStatus === "hidden" ? "批量下架" : "批量恢复",
            action:
              resource === "posts"
                ? "bulkModeratePosts"
                : "bulkModerateComments",
            tone: "danger",
            fields: [
              {
                source: "reason",
                label: "原因",
                required: true,
                kind: "longtext",
              },
            ],
            fixed: {
              ids: Object.keys(selection).filter((id) => selection[id]),
              status: bulkStatus,
            },
            build: (_, v) => v,
          }}
          onClose={() => {
            setBulk(false);
            setSelection({});
          }}
        />
      )}
      {resource === "posts" && <FeedPreview />}
    </>
  );
}
export function RecordForm({
  resource,
  record,
  fields,
  title,
  onClose,
  onSubmit,
  description,
}: {
  resource: string;
  record: RecordData;
  fields: FormFieldConfig[];
  title: string;
  onClose: () => void;
  onSubmit?: (values: RecordData) => Promise<unknown>;
  description?: string;
}) {
  const defaults = Object.fromEntries(
    fields.map((f) => [
      f.source,
      f.kind === "boolean"
        ? initialValue(record, f.source) === true
        : f.kind === "json"
          ? initialValue(record, f.source) || []
          : f.kind === "datetime"
            ? initialValue(record, f.source)
            : initialValue(record, f.source),
    ]),
  );
  const {
      control,
      handleSubmit,
      formState: { isDirty, isSubmitting },
    } = useForm<RecordData>({ defaultValues: defaults }),
    [error, setFailure] = useState<unknown>(null),
    [discard, setDiscard] = useState(false);
  const close = () => {
    if (isDirty) setDiscard(true);
    else onClose();
  };
  const submit = handleSubmit(async (values) => {
    setFailure(null);
    try {
      if (onSubmit) await onSubmit(values);
      else if (record.id)
        await dataProvider.update(resource, {
          id: record.id,
          data: values,
          previousData: record,
        });
      else await dataProvider.create(resource, { data: values });
      toast.success(`${title}成功`);
      await queryClient.invalidateQueries({ queryKey: ["admin"] });
      onClose();
    } catch (err) {
      setFailure(err);
    }
  });
  return (
    <>
      <Dialog open onClose={close} busy={isSubmitting} title={title}>
        <form className="studio-form" onSubmit={submit}>
          {description && <p>{description}</p>}
          {fields.map((field) => (
            <Controller
              key={field.source}
              name={field.source}
              control={control}
              rules={{
                validate: (value) =>
                  !field.required ||
                  (value !== undefined &&
                    value !== null &&
                    value !== "" &&
                    (!(typeof value === "string") ||
                      value.trim().length > 0)) ||
                  "必填",
              }}
              render={({ field: input, fieldState }) => (
                <label>
                  {field.label.replace(" JSON", "")}
                  {field.kind === "json" ? (
                    <ArrayEditor
                      value={input.value}
                      onChange={input.onChange}
                      source={field.source}
                    />
                  ) : field.kind === "boolean" ? (
                    <input
                      type="checkbox"
                      checked={input.value === true}
                      onChange={(e) => input.onChange(e.target.checked)}
                    />
                  ) : field.kind === "image" ? (
                    <input
                      type="file"
                      accept="image/png,image/jpeg"
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        if (file && file.size <= 2097152)
                          input.onChange({ rawFile: file });
                        else if (file)
                          setFailure(new Error("图片不得超过 2 MB"));
                      }}
                    />
                  ) : field.kind === "select" ? (
                    <select {...input} value={input.value ?? ""}>
                      <option value="">请选择</option>
                      {field.choices?.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                    </select>
                  ) : field.kind === "longtext" ? (
                    <textarea {...input} />
                  ) : (
                    <input
                      {...input}
                      value={
                        field.kind === "datetime"
                          ? localDateTime(input.value)
                          : (input.value ?? "")
                      }
                      type={
                        field.kind === "number"
                          ? "number"
                          : field.kind === "password"
                            ? "password"
                            : field.kind === "date"
                              ? "date"
                              : field.kind === "datetime"
                                ? "datetime-local"
                                : "text"
                      }
                      step={field.kind === "number" ? "any" : undefined}
                      onChange={(e) =>
                        input.onChange(
                          field.kind === "number"
                            ? e.target.value === ""
                              ? ""
                              : Number(e.target.value)
                            : field.kind === "datetime" && e.target.value
                              ? new Date(e.target.value).toISOString()
                              : e.target.value,
                        )
                      }
                    />
                  )}{" "}
                  {fieldState.error && (
                    <small role="alert">{fieldState.error.message}</small>
                  )}
                </label>
              )}
            />
          ))}
          {error != null && <ErrorState error={error} />}
          <footer>
            <Button onClick={close} disabled={isSubmitting}>
              取消
            </Button>
            <Button type="submit" variant="primary" disabled={isSubmitting}>
              {isSubmitting ? "正在提交…" : "保存"}
            </Button>
          </footer>
        </form>
      </Dialog>
      <Dialog
        open={discard}
        onClose={() => setDiscard(false)}
        title="放弃未保存的修改？"
      >
        <div className="studio-form">
          <p>修改尚未提交，关闭后会丢失。</p>
          <footer>
            <Button onClick={() => setDiscard(false)}>继续编辑</Button>
            <Button variant="danger" onClick={onClose}>
              放弃修改
            </Button>
          </footer>
        </div>
      </Dialog>
    </>
  );
}
function ArrayEditor({
  value,
  onChange,
  source,
}: {
  value: unknown;
  onChange: (value: unknown) => void;
  source: string;
}) {
  let parsed: unknown = value;
  try {
    if (typeof value === "string") parsed = JSON.parse(value || "[]");
  } catch {
    return <ErrorState error="配置记录格式无效，请刷新并检查数据。" />;
  }
  const array: any[] = Array.isArray(parsed) ? parsed : [];
  const keys =
    source === "calendarEvents"
      ? ["id", "title", "startDateString", "endDateString", "kind"]
      : source === "solarTerms"
        ? ["id", "title", "dateString"]
        : ["id", "title", "startDateString", "endDateString", "kind"];
  return (
    <div className="grid gap-3">
      {array.map((item, index) => (
        <div className="studio-json-row" key={index}>
          {typeof item === "object" && item !== null ? (
            Object.entries(item).map(([key, v]) => (
              <label key={key}>
                {(
                  {
                    id: "记录 ID",
                    title: "标题",
                    startDateString: "开始日期",
                    endDateString: "结束日期",
                    dateString: "日期",
                    start_date: "开始日期",
                    end_date: "结束日期",
                    date_string: "日期",
                    kind: "类型",
                    academicCategory: "学业分类",
                  } as Record<string, string>
                )[key] ?? key}
                <input
                  type={
                    typeof v === "boolean"
                      ? "checkbox"
                      : typeof v === "number"
                        ? "number"
                        : key.toLowerCase().includes("date")
                          ? "date"
                          : "text"
                  }
                  checked={v === true}
                  value={typeof v === "boolean" ? undefined : String(v ?? "")}
                  onChange={(e) =>
                    onChange(
                      array.map((row, i) =>
                        i === index
                          ? {
                              ...row,
                              [key]:
                                typeof v === "boolean"
                                  ? e.target.checked
                                  : typeof v === "number"
                                    ? Number(e.target.value)
                                    : e.target.value,
                            }
                          : row,
                      ),
                    )
                  }
                />
              </label>
            ))
          ) : (
            <input
              value={String(item)}
              onChange={(e) =>
                onChange(
                  array.map((row, i) => (i === index ? e.target.value : row)),
                )
              }
            />
          )}
          <Button onClick={() => onChange(array.filter((_, i) => i !== index))}>
            移除此项
          </Button>
        </div>
      ))}
      <Button
        onClick={() =>
          onChange([
            ...array,
            Object.fromEntries(
              keys.map((key) => [
                key,
                key === "id"
                  ? crypto.randomUUID()
                  : key === "kind"
                    ? "holiday"
                    : "",
              ]),
            ),
          ])
        }
      >
        <Plus size={13} />
        添加记录
      </Button>
    </div>
  );
}
function ActionForm({
  resource,
  record,
  action,
  onClose,
}: {
  resource: string;
  record: RecordData;
  action: RowActionConfig;
  onClose: () => void;
}) {
  const message = actionConfirmation(resource, record, action);
  return (
    <RecordForm
      resource={resource}
      record={{}}
      fields={action.fields ?? []}
      title={action.label}
      description={`${message.summary}。${message.impact} 操作结果会写入审计。`}
      onClose={onClose}
      onSubmit={async (values) => {
        const combined = { ...action.fixed, ...values };
        if (action.action === "__deleteRating")
          return dataProvider.delete(resource, {
            id: record.id,
            previousData: record,
          });
        return dataProvider.execute(
          action.action,
          action.build
            ? action.build(record, combined)
            : { id: record.id, ...combined },
        );
      }}
    />
  );
}
function DetailSheet({
  resource,
  id,
  record,
  onClose,
}: {
  resource: string;
  id: string;
  record?: RecordData;
  onClose: () => void;
}) {
  const { campus, identity } = useAdmin(),
    action = detailActions[resource];
  const detail = useAction<RecordData>(action ?? "unused", { id }, !!action);
  const fallback = useQuery({
    queryKey: ["admin", identity?.admin.id, campus, "record", resource, id],
    queryFn: ({ signal }) =>
      dataProvider.getList(resource, {
        filter: { id, status: "all" },
        pagination: { page: 1, perPage: 1 },
        sort: {
          field: resourceConfigs[resource].defaultSort?.field ?? "created_at",
          order: "DESC",
        },
        signal,
      }),
    enabled: !action && !record,
  });
  return (
    <Dialog
      open
      side
      title={`${resourceConfigs[resource].label}详情`}
      onClose={onClose}
    >
      {(action && detail.isPending) ||
      (!action && !record && fallback.isPending) ? (
        <Loading />
      ) : detail.error || fallback.error ? (
        <ErrorState error={detail.error ?? fallback.error} />
      ) : (
        <RecordDetailContent
          resource={resource}
          detail={detail.data ?? record ?? fallback.data?.data[0] ?? {}}
        />
      )}
    </Dialog>
  );
}
export function RecordDetailContent({
  resource,
  detail,
}: {
  resource: string;
  detail: RecordData;
}) {
  const { identity } = useAdmin();
  const record =
      detail.post ?? detail.profile ?? detail.poll ?? detail.report ?? detail,
    config = resourceConfigs[resource];
  return (
    <div className="studio-detail">
      <h3>
        {record.title ??
          record.question ??
          record.nickname ??
          record.name ??
          config?.label}
      </h3>
      {record.status && <Badge>{valueLabel(record.status)}</Badge>}
      <dl>
        {config?.columns
          .filter(
            (c) =>
              !["body", "images"].includes(c.source) &&
              (resource !== "profiles" ||
                identity?.admin.role === "super_admin" ||
                c.source !== "edu_id"),
          )
          .map((c) => (
            <div key={c.source} className="contents">
              <dt>{c.label}</dt>
              <dd>
                {c.kind === "date"
                  ? dateLabel(valueAt(record, c.source))
                  : valueLabel(valueAt(record, c.source) ?? c.fallback)}
              </dd>
            </div>
          ))}
      </dl>
      {record.body && <p>{record.body}</p>}
      {record.detail && <p>{record.detail}</p>}
      {record.pin && (
        <p>
          {record.pin.scope === "category" ? "分类置顶" : "全局置顶"} · P
          {record.pin.priority} · {dateLabel(record.pin.starts_at)} —{" "}
          {dateLabel(record.pin.ends_at)}
        </p>
      )}
      {record.images?.map((image: RecordData, i: number) => (
        <a
          key={image.id ?? i}
          href={image.signed_url}
          target="_blank"
          rel="noreferrer"
        >
          <img
            src={image.thumbnail_signed_url ?? image.signed_url}
            alt={`帖子图片 ${i + 1}`}
          />
        </a>
      ))}
      {record.attachments?.map((a: RecordData) => (
        <a
          className="studio-card"
          key={a.id}
          href={a.preview_signed_url}
          target="_blank"
          rel="noreferrer"
        >
          {a.display_name} · {a.byte_size} 字节 · {a.sha256}
        </a>
      ))}
      {record.options?.map((o: RecordData) => (
        <p key={o.id}>
          {o.text} · {o.vote_count} 票
        </p>
      ))}
      {["comments", "recentPosts", "recentComments", "auditLogs"].map((key) =>
        detail[key]?.length ? (
          <section key={key}>
            <h3>
              {
                (
                  {
                    comments: "评论",
                    recentPosts: "最近帖子",
                    recentComments: "最近评论",
                    auditLogs: "管理审计",
                  } as Record<string, string>
                )[key]
              }
            </h3>
            {detail[key].map((r: RecordData) => (
              <p key={r.id}>
                {r.title ?? r.body ?? r.action} · {dateLabel(r.created_at)}
              </p>
            ))}
          </section>
        ) : null,
      )}
      {detail.evidence?.post && (
        <RecordDetailContent resource="posts" detail={detail.evidence.post} />
      )}{" "}
      {detail.evidence?.comment && <p>{detail.evidence.comment.body}</p>}{" "}
      {resource === "reports" && record.post && (
        <Link className="studio-button" to={`/posts/${record.post.id}`}>
          查看被举报帖子
        </Link>
      )}
    </div>
  );
}
function FeedPreview() {
  const query = useAction<{ posts: RecordData[] }>("previewCommunityFeed", {
    limit: 20,
  });
  return (
    <section className="studio-card" style={{ marginTop: 24 }}>
      <div className="studio-card-header">
        <h2>客户端 Feed 预览</h2>
        <Button onClick={() => void query.refetch()}>刷新预览</Button>
      </div>
      {query.error ? (
        <ErrorState error={query.error} />
      ) : (
        <div className="studio-queue-items">
          {query.data?.posts.map((post, index) => (
            <Link key={post.id} to={`/posts/${post.id}`}>
              <span>
                #{index + 1} {post.title}
              </span>
              {post.pin && (
                <Badge>
                  {post.pin.scope === "category" ? "分类置顶" : "全局置顶"}
                </Badge>
              )}
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}
export function dateLabel(value: unknown) {
  if (!value) return "—";
  const date = new Date(String(value));
  return Number.isFinite(date.getTime())
    ? date.toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" })
    : String(value);
}
function localDateTime(value: unknown) {
  if (!value) return "";
  const d = new Date(String(value));
  if (!Number.isFinite(d.getTime())) return "";
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
}
