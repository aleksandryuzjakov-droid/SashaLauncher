#pragma once
#include <commdlg.h>
#include <array>
#pragma comment(lib,"comdlg32.lib")
namespace SkinEditor {
using Pixels=std::array<ARGB,4096>;
Pixels pixels{};
std::vector<Pixels> undo,redo;
HWND hwnd{};bool initialized=false,drawing=false,eraser=false,grid=true,dirty=false;
ARGB ink=0xffba8765;int lastX=-1,lastY=-1;float zoom=1;
const int CanvasX=24,CanvasY=94,Cell=8;
wstring StoredPath(){return (std::filesystem::path(configPath).parent_path()/L"skin.png").wstring();}
void Push(){undo.push_back(pixels);if(undo.size()>64)undo.erase(undo.begin());redo.clear();}
void Mark(){dirty=true;SetWindowTextW(hwnd,L"Sanie — редактор скина *");InvalidateRect(hwnd,nullptr,FALSE);}
void RectPixels(int x,int y,int w,int h,ARGB c){for(int yy=y;yy<y+h;yy++)for(int xx=x;xx<x+w;xx++)pixels[yy*64+xx]=c;}
void Template(){
    pixels.fill(0);
    // Classic 64x64 UV layout: only base-layer islands are initialized.
    RectPixels(0,0,32,16,0xffb78162);RectPixels(0,0,32,8,0xff503c2d);
    RectPixels(8,8,8,2,0xff503c2d);RectPixels(9,11,2,1,0xffcbd8ef);RectPixels(13,11,2,1,0xffcbd8ef);
    RectPixels(10,11,1,1,0xff44458a);RectPixels(13,11,1,1,0xff44458a);RectPixels(11,14,2,1,0xff694c39);
    RectPixels(16,16,24,16,0xff328d96);RectPixels(0,16,16,16,0xff4c4c88);
    RectPixels(40,16,16,16,0xffb78162);RectPixels(40,20,16,4,0xff328d96);
    RectPixels(16,48,16,16,0xff4c4c88);RectPixels(32,48,16,16,0xffb78162);RectPixels(32,52,16,4,0xff328d96);
}
bool ReadPNG(const wchar_t* path,Pixels& out){
    Bitmap image(path);if(image.GetLastStatus()!=Ok||image.GetWidth()!=64||image.GetHeight()!=64)return false;
    for(int y=0;y<64;y++)for(int x=0;x<64;x++){Color c;if(image.GetPixel(x,y,&c)!=Ok)return false;out[y*64+x]=c.GetValue();}return true;
}
bool WritePNG(const wchar_t* path){
    Bitmap image(64,64,PixelFormat32bppARGB);
    for(int y=0;y<64;y++)for(int x=0;x<64;x++)image.SetPixel(x,y,Color(pixels[y*64+x]));
    UINT count=0,bytes=0;GetImageEncodersSize(&count,&bytes);if(!bytes)return false;
    std::vector<BYTE> buffer(bytes);auto enc=(ImageCodecInfo*)buffer.data();if(GetImageEncoders(count,bytes,enc)!=Ok)return false;
    for(UINT i=0;i<count;i++)if(wcscmp(enc[i].MimeType,L"image/png")==0)return image.Save(path,&enc[i].Clsid,nullptr)==Ok;
    return false;
}
void Saved(){dirty=false;SetWindowTextW(hwnd,L"Sanie — редактор скина");}
bool Save(){wstring path=StoredPath();if(!WritePNG(path.c_str())){MessageBoxW(hwnd,L"Не удалось сохранить skin.png",L"Sanie",MB_ICONERROR);return false;}Saved();return true;}
bool Confirm(){if(!dirty)return true;int r=MessageBoxW(hwnd,L"Сохранить изменения в skin.png?",L"Редактор скина",MB_YESNOCANCEL|MB_ICONQUESTION);return r==IDNO||(r==IDYES&&Save());}
void FileDialog(bool save){
    wchar_t path[32768]=L"skin.png";OPENFILENAMEW of{};of.lStructSize=sizeof(of);of.hwndOwner=hwnd;
    of.lpstrFilter=L"PNG 64 x 64\0*.png\0";of.lpstrFile=path;of.nMaxFile=32768;of.lpstrDefExt=L"png";
    of.Flags=OFN_EXPLORER|OFN_NOCHANGEDIR|OFN_PATHMUSTEXIST|(save?OFN_OVERWRITEPROMPT:OFN_FILEMUSTEXIST);
    if(!(save?GetSaveFileNameW(&of):GetOpenFileNameW(&of)))return;
    if(save){if(!WritePNG(path))MessageBoxW(hwnd,L"Ошибка экспорта PNG",L"Sanie",MB_ICONERROR);}
    else {Pixels imported;if(!ReadPNG(path,imported)){MessageBoxW(hwnd,L"Нужен PNG размером ровно 64×64. Старые скины 64×32 не поддерживаются.",L"Sanie",MB_ICONWARNING);return;}Push();pixels=imported;Mark();}
}
void Choose(){static COLORREF custom[16]{};CHOOSECOLORW cc{};cc.lStructSize=sizeof(cc);cc.hwndOwner=hwnd;cc.rgbResult=RGB((ink>>16)&255,(ink>>8)&255,ink&255);cc.lpCustColors=custom;cc.Flags=CC_FULLOPEN|CC_RGBINIT;
    if(ChooseColorW(&cc)){ink=0xff000000|((ARGB)GetRValue(cc.rgbResult)<<16)|((ARGB)GetGValue(cc.rgbResult)<<8)|GetBValue(cc.rgbResult);eraser=false;InvalidateRect(hwnd,nullptr,FALSE);}}
void Dot(int x,int y){if(x>=0&&x<64&&y>=0&&y<64)pixels[y*64+x]=eraser?0:ink;}
void Stroke(int x,int y){
    if(lastX<0){Dot(x,y);}else{int ax=lastX,ay=lastY,dx=abs(x-ax),sx=ax<x?1:-1,dy=-abs(y-ay),sy=ay<y?1:-1,err=dx+dy;
        for(;;){Dot(ax,ay);if(ax==x&&ay==y)break;int e=2*err;if(e>=dy){err+=dy;ax+=sx;}if(e<=dx){err+=dx;ay+=sy;}}}
    lastX=x;lastY=y;Mark();
}
void PixelsPreview(Graphics& g,int sx,int sy,int w,int h,float x,float y,float factor){
    for(int yy=0;yy<h;yy++)for(int xx=0;xx<w;xx++){SolidBrush b(Color(pixels[(sy+yy)*64+sx+xx]));g.FillRectangle(&b,x+xx*factor,y+yy*factor,factor,factor);}
}
void Tool(Graphics& g,int id,float x,float y,float w,const wchar_t* label,bool active=false){
    Box(g,RectF(x,y,w,34),active?theme.accent:theme.raised,8,true);
    Text(g,label,x,y,w,34,12,active?C(10,44,30):theme.text,true,1);
}
void Paint(){PAINTSTRUCT ps{};HDC dc=BeginPaint(hwnd,&ps);RECT r{};GetClientRect(hwnd,&r);
    if(r.right>0&&r.bottom>0){Bitmap back(r.right,r.bottom,PixelFormat32bppPARGB);{Graphics g(&back);g.Clear(theme.bg);g.ScaleTransform(zoom,zoom);g.SetSmoothingMode(SmoothingModeAntiAlias);g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    Text(g,L"Редактор скина",24,10,430,36,23,theme.text,true);
    Tool(g,1,24,52,90,L"Карандаш",!eraser);Tool(g,2,122,52,80,L"Ластик",eraser);Tool(g,3,210,52,80,L"Цвет");Tool(g,4,298,52,70,L"Отмена");Tool(g,5,376,52,70,L"Повтор");Tool(g,6,454,52,82,L"Сетка",grid);
    g.SetSmoothingMode(SmoothingModeNone);
    for(int y=0;y<64;y++)for(int x=0;x<64;x++){SolidBrush b(((x+y)%2)?C(65,72,75):C(46,53,56));g.FillRectangle(&b,CanvasX+x*Cell,CanvasY+y*Cell,Cell,Cell);SolidBrush p(Color(pixels[y*64+x]));g.FillRectangle(&p,CanvasX+x*Cell,CanvasY+y*Cell,Cell,Cell);}
    if(grid)for(int i=0;i<=64;i++){Color c=i%8==0?C(200,220,210,100):C(200,220,210,25);Line(g,24+i*8.f,94,24+i*8.f,606,c);Line(g,24,94+i*8.f,536,94+i*8.f,c);}
    Box(g,RectF(560,94,312,390),theme.card,14,true);Text(g,L"Предпросмотр • classic",580,107,270,29,16,theme.text,true);
    PixelsPreview(g,8,8,8,8,648,155,8);PixelsPreview(g,20,20,8,12,648,219,8);
    PixelsPreview(g,44,20,4,12,616,219,8);PixelsPreview(g,36,52,4,12,712,219,8);
    PixelsPreview(g,4,20,4,12,648,315,8);PixelsPreview(g,20,52,4,12,680,315,8);
    Text(g,L"Спереди • базовый слой",580,433,270,26,12,theme.muted);
    SolidBrush chosen{Color(ink)};g.FillRectangle(&chosen,560,502,34,34);Text(g,eraser?L"Прозрачность":L"Текущий цвет",608,502,240,34,14,theme.text);
    Tool(g,7,560,554,148,L"Импорт PNG");Tool(g,8,724,554,148,L"Экспорт PNG");Tool(g,9,560,598,148,L"Шаблон");Tool(g,10,724,598,148,L"Сохранить",true);
    Text(g,L"ЛКМ — рисовать  •  ПКМ — пипетка  •  Ctrl+Z / Ctrl+Y / Ctrl+S",24,620,512,27,11,theme.muted);
    Text(g,L"64×64 • classic / руки 4 px • все UV-слои доступны на холсте",24,647,850,25,12,theme.muted);
    Text(g,L"PNG сохраняется локально. Для показа в offline-игре нужен отдельный мод.",24,674,850,25,12,theme.muted);
    }Graphics screen(dc);screen.DrawImage(&back,0,0);}EndPaint(hwnd,&ps);}
int ToolAt(float x,float y){
    const RectF rects[]={RectF(24,52,90,34),RectF(122,52,80,34),RectF(210,52,80,34),RectF(298,52,70,34),RectF(376,52,70,34),RectF(454,52,82,34),RectF(560,554,148,34),RectF(724,554,148,34),RectF(560,598,148,34),RectF(724,598,148,34)};
    for(int i=0;i<10;i++)if(rects[i].Contains(x,y))return i+1;return 0;
}
void Action(int id){switch(id){case 1:eraser=false;break;case 2:eraser=true;break;case 3:Choose();break;
    case 4:if(!undo.empty()){redo.push_back(pixels);pixels=undo.back();undo.pop_back();Mark();}break;
    case 5:if(!redo.empty()){undo.push_back(pixels);pixels=redo.back();redo.pop_back();Mark();}break;
    case 6:grid=!grid;break;case 7:FileDialog(false);break;case 8:FileDialog(true);break;
    case 9:if(MessageBoxW(hwnd,L"Заменить холст шаблоном? Действие можно отменить.",L"Sanie",MB_YESNO)==IDYES){Push();Template();Mark();}break;
    case 10:Save();break;}InvalidateRect(hwnd,nullptr,FALSE);}
LRESULT CALLBACK Proc(HWND h,UINT msg,WPARAM wp,LPARAM lp){switch(msg){
    case WM_SIZE:{RECT r{};GetClientRect(h,&r);zoom=std::max(.1f,std::min(r.right/896.f,r.bottom/712.f));InvalidateRect(h,nullptr,FALSE);return 0;}
    case WM_ERASEBKGND:return 1;case WM_PAINT:Paint();return 0;
    case WM_LBUTTONDOWN:case WM_RBUTTONDOWN:{SetFocus(h);float x=GET_X_LPARAM(lp)/zoom,y=GET_Y_LPARAM(lp)/zoom;
        if(RectF(24,94,512,512).Contains(x,y)){int px=(int)(x-24)/8,py=(int)(y-94)/8;
            if(msg==WM_RBUTTONDOWN){ink=pixels[py*64+px];if(!(ink>>24))ink=0xff000000;eraser=false;InvalidateRect(h,nullptr,FALSE);}
            else{Push();drawing=true;lastX=lastY=-1;SetCapture(h);Stroke(px,py);}}
        else if(msg==WM_LBUTTONDOWN)Action(ToolAt(x,y));return 0;}
    case WM_MOUSEMOVE:if(drawing){float x=GET_X_LPARAM(lp)/zoom,y=GET_Y_LPARAM(lp)/zoom;if(RectF(24,94,512,512).Contains(x,y))Stroke((int)(x-24)/8,(int)(y-94)/8);else lastX=lastY=-1;}return 0;
    case WM_LBUTTONUP:drawing=false;lastX=lastY=-1;if(GetCapture()==h)ReleaseCapture();return 0;
    case WM_CAPTURECHANGED:drawing=false;lastX=lastY=-1;return 0;
    case WM_KEYDOWN:if(GetKeyState(VK_CONTROL)&0x8000){if(wp=='Z')Action(4);if(wp=='Y')Action(5);if(wp=='S')Action(10);}return 0;
    case WM_CLOSE:if(Confirm())DestroyWindow(h);return 0;
    case WM_DESTROY:if(dirty){initialized=false;dirty=false;undo.clear();redo.clear();}hwnd=nullptr;return 0;
    }return DefWindowProcW(h,msg,wp,lp);}
void Open(){
    if(hwnd){ShowWindow(hwnd,SW_RESTORE);SetForegroundWindow(hwnd);return;}
    if(!initialized){Template();Pixels loaded;if(ReadPNG(StoredPath().c_str(),loaded))pixels=loaded;initialized=true;}
    HINSTANCE inst=GetModuleHandleW(nullptr);WNDCLASSW wc{};wc.lpfnWndProc=Proc;wc.hInstance=inst;wc.lpszClassName=L"SanieSkinEditor";wc.hCursor=LoadCursorW(nullptr,IDC_CROSS);RegisterClassW(&wc);
    hwnd=CreateWindowExW(0,wc.lpszClassName,L"Sanie — редактор скина",WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,CW_USEDEFAULT,928,770,windowHandle,nullptr,inst,nullptr);
    if(hwnd){ShowWindow(hwnd,SW_SHOW);UpdateWindow(hwnd);}else MessageBoxW(windowHandle,L"Не удалось открыть редактор",L"Sanie",MB_ICONERROR);
}
}
