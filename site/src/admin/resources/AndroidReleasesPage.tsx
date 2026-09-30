import {useEffect, useState} from 'react';
import {Datagrid, DateField, FunctionField, List, TextField, useCanAccess, useListContext, useNotify, useRecordContext, useRefresh} from 'react-admin';
import {Alert, Box, Button, Checkbox, Chip, Dialog, DialogActions, DialogContent, DialogTitle, FormControlLabel, Stack, Typography} from '@mui/material';
import {actionRequest} from '../providers/client';

type Release={id:string;versionName:string;versionCode:number;status:string;releaseNotes:string;sizeBytes:number;commit:string;sha256:string;certificateSha256:string;errorCode?:string;runUrl?:string;githubReleaseUrl:string};
const statuses:Record<string,string>={ready:'待发布',publishing:'发布中',published:'已发布',failed:'发布失败',revoked:'已撤回'};

export function AndroidReleasesPage(){
  return <Box>
    <Typography variant="h5" sx={{my:2}}>Android 版本</Typography>
    <Alert severity="info" sx={{mb:2}}>先下载候选包验收，再决定发布。正式发布使用同一份安装包；iOS 继续在 App Store Connect 发布。</Alert>
    <List title="Android 版本" perPage={20} sort={{field:'versionCode',order:'DESC'}} exporter={false} empty={<Typography sx={{p:3}}>暂无候选或正式版本。主线版本更新并通过检查后，候选包会显示在这里。</Typography>}>
      <PublicationPolling />
      <Datagrid bulkActionButtons={false} rowClick={false}>
        <TextField source="versionName" label="版本" />
        <FunctionField label="状态" render={(r:Release)=><Chip size="small" label={statuses[r.status]??r.status} color={r.status==='failed'?'error':r.status==='published'?'success':'default'} />} />
        <FunctionField label="安装包" render={(r:Release)=>`${(r.sizeBytes/1024/1024).toFixed(1)} MB`} />
        <DateField source="published_at" label="发布时间" showTime />
        <FunctionField label="操作" render={()=><ReleaseActions />} />
      </Datagrid>
    </List>
  </Box>;
}
function PublicationPolling(){
  const {data}=useListContext<Release>();const refresh=useRefresh();
  const active=data?.some(r=>r.status==='publishing');
  useEffect(()=>{if(!active)return;const timer=setInterval(refresh,10000);return ()=>clearInterval(timer);},[active,refresh]);return null;
}
function ReleaseActions(){
  const record=useRecordContext<Release>()!;const {canAccess}=useCanAccess({resource:'android-releases',action:'edit'});
  const [dialog,setDialog]=useState<'details'|'publish'|'revoke'|null>(null),[accepted,setAccepted]=useState(false),[busy,setBusy]=useState(false);
  const refresh=useRefresh(),notify=useNotify();
  const close=()=>{if(!busy){setDialog(null);setAccepted(false);}};
  async function submit(){
    setBusy(true);
    try{
      await actionRequest(dialog==='revoke'?'revokeAndroidRelease':'requestAndroidPublication',{id:record.id,...(dialog==='publish'?{accepted}: {})});
      setDialog(null);setAccepted(false);notify(dialog==='revoke'?'版本已撤回':'发布任务已提交，正在核对发行结果。',{type:'info'});
    }catch(error){notify(error instanceof Error?error.message:'操作失败，请刷新后重试。',{type:'error'});}
    finally{setBusy(false);refresh();}
  }
  return <>
    <Stack direction="row" spacing={1} flexWrap="wrap">
      <Button size="small" onClick={()=>setDialog('details')}>详情</Button>
      {['ready','failed'].includes(record.status)&&<Button size="small" component="a" href={`/api/admin/android-candidate?id=${encodeURIComponent(record.id)}`}>下载验收</Button>}
      {canAccess&&['ready','failed'].includes(record.status)&&<Button size="small" onClick={()=>setDialog('publish')}>{record.status==='failed'?'重试发布':'发布'}</Button>}
      {canAccess&&record.status==='published'&&<Button size="small" color="error" onClick={()=>setDialog('revoke')}>撤回</Button>}
    </Stack>
    <Dialog open={dialog!==null} onClose={close} fullWidth maxWidth="sm">
      <DialogTitle>{dialog==='details'?'版本详情':dialog==='revoke'?'撤回版本':'发布 Android 版本'} {record.versionName}</DialogTitle>
      <DialogContent>
        <Typography sx={{whiteSpace:'pre-wrap',mb:2}}>{record.releaseNotes}</Typography>
        {dialog==='publish'&&<><Alert severity="info">发布后，官网提供下载，App 提示更新。发布使用你已经下载验收的同一份 APK。</Alert><FormControlLabel control={<Checkbox checked={accepted} onChange={e=>setAccepted(e.target.checked)} />} label="我已完成候选包验收，确认发布此版本" /></>}
        {dialog==='revoke'&&<Alert severity="warning">撤回后，官网和 App 不再推荐此版本。已安装的版本需要通过后续更新修复。</Alert>}
        {dialog==='details'&&<Stack spacing={1} sx={{overflowWrap:'anywhere'}}>
          <Typography>状态：{statuses[record.status]}</Typography><Typography>版本号：{record.versionCode}</Typography>
          {record.errorCode&&<Alert severity="error">发布未完成（{record.errorCode}）。请查看任务结果后重试。</Alert>}
          <Typography variant="body2">源码：{record.commit}</Typography><Typography variant="body2">SHA-256：{record.sha256}</Typography>
          <Typography variant="body2">签名：{record.certificateSha256}</Typography>
          {record.runUrl&&<Button component="a" href={record.runUrl} target="_blank" rel="noreferrer">查看发布任务</Button>}
          {record.status==='published'&&<Button component="a" href={record.githubReleaseUrl} target="_blank" rel="noreferrer">GitHub 镜像</Button>}
        </Stack>}
      </DialogContent>
      <DialogActions><Button disabled={busy} onClick={close}>{dialog==='details'?'关闭':'取消'}</Button>
        {dialog!=='details'&&<Button disabled={busy||(dialog==='publish'&&!accepted)} onClick={submit} color={dialog==='revoke'?'error':'primary'}>{busy?'正在提交…':dialog==='revoke'?'确认撤回':'确认发布'}</Button>}
      </DialogActions>
    </Dialog>
  </>;
}
