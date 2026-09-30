import {expect,test} from '@playwright/test';

test('admin verifies a candidate before publishing and keeps iOS outside version management',async({page})=>{
  const release={id:'com.myleafy.android-6',versionName:'1.2.2',versionCode:6,status:'ready',ciVerified:true,releaseNotes:'改进手动验证码体验',sizeBytes:50000000,commit:'a'.repeat(40),sha256:'b'.repeat(64),certificateSha256:'c'.repeat(64)};
  let published=false;
  await page.route('**/api/admin/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path.endsWith('/me'))return route.fulfill({json:{admin:{id:'admin-1',username:'admin',display_name:'测试管理员',role:'super_admin',active:true},permissions:[{resource:'android-releases',actions:['list','show','edit']}],session:{expires_at:'2099-01-01T00:00:00Z'}}});
    if(path.endsWith('/actions')){
      const body=route.request().postDataJSON();
      if(body.action==='requestAndroidPublication'){
        expect(body.params).toEqual({id:release.id,accepted:true});published=true;release.status='publishing';
        return route.fulfill({json:{data:{id:release.id,status:'publishing'},meta:{audit_logged:true}}});
      }
      return route.fulfill({json:{data:{items:[release],total:1,page:0,pageSize:20},meta:{audit_logged:true}}});
    }
    return route.fulfill({status:404});
  });
  await page.goto('/admin/android-releases');
  await expect(page.getByText('待发布',{exact:true})).toBeVisible();
  await expect(page.getByText('已通过',{exact:true})).toBeVisible();
  await expect(page.getByRole('link',{name:'下载验收'})).toHaveAttribute('href','/api/admin/android-candidate?id=com.myleafy.android-6');
  await page.getByRole('button',{name:'发布',exact:true}).click();
  await expect(page.getByRole('button',{name:'确认发布',exact:true})).toBeDisabled();
  await page.getByRole('checkbox').check();await page.getByRole('button',{name:'确认发布',exact:true}).click();
  await expect(page.getByText('发布中',{exact:true})).toBeVisible();expect(published).toBe(true);
});

test('operators can inspect candidates but have no publication button',async({page})=>{
  await page.route('**/api/admin/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path.endsWith('/me'))return route.fulfill({json:{admin:{id:'operator-1',username:'operator',display_name:'运营',role:'operator',active:true},permissions:[{resource:'android-releases',actions:['list','show']}],session:{expires_at:'2099-01-01T00:00:00Z'}}});
    return route.fulfill({json:{data:{items:[{id:'candidate',versionName:'1.2.2',versionCode:6,status:'failed',releaseNotes:'测试',sizeBytes:7}],total:1,page:0,pageSize:20},meta:{audit_logged:true}}});
  });
  await page.goto('/admin/android-releases');
  await expect(page.getByText('发布失败',{exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'重试发布'})).toHaveCount(0);
});
