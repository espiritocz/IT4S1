function []=it4s1_stamps2csv()
% based on PS_OUTPUT by A. Hooper and RemotWatch export tool by P. Guimaraes
% rearranged by Milan Lazecky, 2017-2018
%

fprintf('Exporting to exported.csv...\n')
%currently will always perform first-value-to-zero (needed for non-experts..)
refzero=1;
deramp=getparm('scla_deramp',1);
if deramp=='y'
 deramp=1;
else
 deramp=0;
end

small_baseline_flag=getparm('small_baseline_flag',1);
ref_vel=getparm('ref_velocity',1);
lambda=getparm('lambda',1);

load psver
psname=['ps',num2str(psver)];
rcname=['rc',num2str(psver)];
phuwname=['phuw',num2str(psver)];
sclaname=['scla',num2str(psver)];
hgtname=['hgt',num2str(psver)];
scnname=['scn',num2str(psver)];
mvname=['mv',num2str(psver)];
meanvname=['mean_v'];

ps=load(psname);
phuw=load(phuwname);
rc=load(rcname);

n_image=ps.n_image;

ijname=['ps_ij.txt'];
ij=ps.ij(:,2:3);
save(ijname,'ij','-ASCII');

llname=['ps_ll.txt'];
lonlat=ps.lonlat;
save(llname,'lonlat','-ASCII');

datename=['date.txt'];
date_out=str2num(datestr(ps.day,'yyyymmdd'));
save(datename,'date_out','-ASCII','-DOUBLE');

master_ix=sum(ps.master_day>ps.day)+1;

%relating unwrapped phase to reference point(s?)
ref_ps=ps_setref;
%ph_uw=phuw.ph_uw-repmat(mean(phuw.ph_uw(ref_ps,:)),ps.n_ps,1);

scla=load(sclaname);
hgt=load(hgtname);

%removing SCLA and master APS (this something called C_ps_uw)
ph_uw=phuw.ph_uw - scla.ph_scla - repmat(scla.C_ps_uw,1,n_image);

%Remove APS (a_l now only) if available and if correct
if exist('tca2.mat','file')
 aps=load('tca2');
 [aps_corr,fig_name_tca] = ps_plot_tca(aps,'a_l');
 if length(aps_corr)==length(ph_uw)
  ph_uw=ph_uw - aps_corr; 
 end
end

%if given to deramp ('o'), then deramp J
if deramp==1
 [ph_uw] = ps_deramp(ps,ph_uw);     % deramping ifgs
end

% this is only approximate
K_ps_uw=scla.K_ps_uw-mean(scla.K_ps_uw);
dem_error=double(K2q(K_ps_uw,ps.ij(:,3)));

clear scla phuw

%recompute towards reference point
ph_uw=ph_uw-repmat(mean(ph_uw(ref_ps,:)),ps.n_ps,1);

%original stamps approach (including std dev) is here:
ps_mean_v([],1500,'d');
meanv2=load('mv2.mat');
mean_v2=-meanv2.mean_v;
meanv=load(meanvname);
mean_v=-meanv.m(2,:)'*365.25/4/pi*lambda*1000+ref_vel*1000; % m(1,:) is master APS + mean deviation from model

mean_v_name=['ps_mean_v.xy'];
mean_v=[ps.lonlat,double(mean_v)];
save(mean_v_name,'mean_v','-ASCII');

%export to CSV (IT4S1 format)
co=load('pm2');

%prepare day numbering to header
%thanks to Pedro Guimaraes, Porto
Day         = ps.day;
ndays        = length(Day);
alldays      = [Day'];
date_string  = datestr (alldays, 1);
[dateseries] = Day';
dateseries   = dateseries';
date_string  = datestr (dateseries, 1);
pedro        = mat2str(date_string);
date_str     = datestr (Day, 1);
pedro        = mat2str(date_str);
pedro2       = strrep(pedro,';',',');
pedro3       = strrep(pedro2,'[','');
pedro4       = strrep(pedro3,']','');
pedro5       = strrep(pedro4,char(39),'');
clear nome
clear strbeg
nome   = '%3.1f,';
nome1  = '%3.1f,';
strend = '%3.1f\n';
number = ndays;
strbeg ='%1.0f,%1.0f,%1.0f,%3.6f,%3.6f,%3.1f,%3.1f,%3.1f,%3.1f,%3.1f,%3.1f,%3.2f,';
for i = 2:number
    if i==number
        nome  =[strbeg nome strend];
    else
        nome=[ nome nome1];
    end
end

%get values to export
number_point = ps.ij(:,1);
y_radar   = ps.ij(:,2);
x_radar   = ps.ij(:,3);
lat_geog  = ps.lonlat(:,2);
long_geog = ps.lonlat(:,1);
velo      = mean_v(:,3);
height    = hgt.hgt;
if isfield(co,'coh_ps');
    %stamps coherence is weird.. will recompute it from ph_uw
    %coher     = co.coh_ps;
    [n_itf,n_pt]=size(ph_uw');
    coher=zeros(n_pt,1);
    for i=1:n_pt,
        coher(i)=abs(sum(exp(-j*detrend(ph_uw(i,:))))/n_itf);
    end;
   % coher=coher';
else
    a=load('phuw_sb_res2');
    res=a.ph_res';
    [n_itf,n_pt]=size(res);   %pokud je ta matice otocena, tak ji transponuj, nebo krome toho, ze prehodis tyhle dve promenne, zmen taky res(:,i) na res(i,:) nize
    coher=zeros(n_pt,1);
    for i=1:n_pt,
        coher(i)=abs(sum(exp(-j*res(:,i)))/n_itf);
    end;
end
%coher     = co.coh_ps;
height_wrt   = dem_error;

%sigma_height = zeros(size(number_point));
%sigma_vel    = zeros(size(number_point));

%computation of std dev thanks to Ivana Hlavacova
%std_dev of one measurement, based on coherence
%std_dev_one=lambda/(4*pi)*sqrt(-2*log(coher)); % m
%variance based on definition of temporal coherence - thanks to Matlab function
%found by Matus Bakon

% but I don't trust stamps-based coh!
variance=2^(1/2)*(-log(coher)).^(1/2);
varbtemp=var((ps.day-ps.master_day)/365.25,1); % years^2
M=n_image-1; %no. of interferogram in PS
%%sigma_vel=(1000*lambda/(4*pi))*(1000*std_dev_one/(sqrt(M*varbtemp))); % mm/year
%%sigma_vel3=(1000*lambda/(4*pi))*sqrt((1000*std_dev_one).^2/M*varbtemp); % mm/year
%sigma_vel=(1000*lambda/(4*pi))*sqrt(variance/(M*varbtemp)); % mm/year
sigma_vel=meanv2.mean_v_std;

load('la2');
lookangle=mean(la); %*180/pi;
range=799299.5124420831; % m
if strcmpi(small_baseline_flag,'y')
    M=ps.n_ifg;
end
varbperp=var(ps.bperp,1); % m^2

%another attempt to comput coherence
%sigma=(4*pi/(lambda*1000))*sigma_vel*sqrt(M)*varbtemp; %(za predpokladu, ze sigma_vel mas v mm/r, lambdu v mm a btemp v letech)
%coher=exp(-sigma^2/2);

%%sigma_height=(lambda*range*sin(lookangle)/(4*pi))*sqrt(std_dev_one.^2/(M*varbperp));


sigma_height=(lambda*range*sin(lookangle)/(4*pi))*sqrt(variance/(M*varbperp)); % m

%convert unwrapped phase to metric units
ph_uw=-ph_uw*lambda*1000/4/pi;

%make the first value to 'almost' zero
cum_disp=zeros(n_pt,1);
if refzero==1
 for i=1:ps.n_ps
  lina=ph_uw(i,:);  
  linx=lina-mean([lina(1) lina(2) lina(3)]);
  ph_uw(i,:)=linx;
  cum_disp(i)=lina(n_image) - mean([lina(1) lina(2) lina(3)]);
 end
end

%cum_disp = ph_uw(:,n_image) - ph_uw(:,1);

%export it all
header = ['ID,','SVET,','LVET,','LAT,','LON,','HEIGHT,','HEIGHT WRT DEM,','SIGMA HEIGHT,','VEL,','SIGMA VEL,','CUM DISP,','COHER,',pedro5];
matr=[number_point, x_radar, y_radar, lat_geog, long_geog, height, height_wrt, sigma_height, velo, sigma_vel, cum_disp, coher, ph_uw()];
fid = fopen('exported.csv', 'w');
fprintf(fid,header);
fprintf(fid,'\n');
fprintf(fid,nome,matr');
fclose(fid);

%to KML
%ps_plot(‘V-DOS’,-1)
%load ps_plot_v-dos ph_disp
%figure;scatter3(lonlat(:,1),lonlat(:,2),ph_disp(:),3,ph_disp(:),'filled');
%view([0 90]);colormap(jet);colormap(fliplr(colormap));caxis([-25 10]);
%gescatter('out.kml',lonlat(:,1),lonlat(:,2),ph_disp(:),'scale',0.3,'clims',[-25 10],'colormap',fliplr(jet),'opacity',1)