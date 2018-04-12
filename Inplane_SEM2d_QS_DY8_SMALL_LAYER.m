% Quasi-static + dynamic modeling of earthquake nucleation using 2D anti-plane SEM
% Variable time stepping has added
% Jacobi preconditioner added
% Output variables saved in one single file

%%%%%%%%%%%%%%%%%%% modified smooth ICs %%%%%%%%%%%%%%%%%%%%%%%%%%%
% a = 0.0144
% b = 0.0191
% L = 42 mm

if ~restart
%------------------------------------------
clearvars -except restart; close all;
bound = 100;
%%%%%%%%%%% Initial Conditions and state variable evolution %%%%%%%%%%%%%%%

% If IDinitCond = 1, use SCEC initial conditions
% If IDinitCond = 2, use smooth initial conditions
IDintitCond = 2;

% If IDstate = 1, compute psi(t+dt) = psi(t) + dt * dpsi(t)/dt
% If IDstate = 2, compute psi(t+dt) by integration with constant V
% If IDstate = 3, compute psi(t+dt) of slip law by integration with constant V
IDstate = 2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% STEP 1: SPECTRAL ELEMENT MESH GENERATION

%**** Set here the parameters of the square box domain and mesh : ****
distN = 1000;
NSIZE = 2;
LX = NSIZE*45e3/distN;
LY = NSIZE*30e3/distN;

yr2sec = 365*24*60*60;
tevent = 197392769.833719193;  % target event time (s)

if IDintitCond == 1
    Total_time = 4.5;    % total time (sec) for SECE initial conditions
elseif IDintitCond == 2 || IDintitCond == 3
    Total_time = 100*yr2sec; %22*yr2sec;  %250*yr2sec;
    %Total_time = 39.5;  % total time (sec) for soothe IC
end
   
%%% Note: I use st_node_space = '3_16' in the paper
%st_node_space = '1_8';  NELX = 90; NELY = 60; P = 4;
%st_node_space = '3_16'; NELX = 60; NELY = 40; P = 4;
%st_node_space = '1_4';  NELX = 45; NELY = 30; P = 4; 
%st_node_space = '3_8';  NELX = 30; NELY = 20; P = 4; 
st_node_space = '3_4';  NELX = 9; NELY = 6; P = 4; 

NELX = NELX*NSIZE;
NELY = NELY*NSIZE;

dxe = LX/NELX;
dye = LY/NELY;
NEL = NELX*NELY;
NGLL = P+1; % number of GLL nodes per element

%[iglob,x,y] = MeshBox(LX,LY,NELX,NELY,NGLL);

XGLL = GetGLL(NGLL);   % local cordinate of GLL quadrature points
periodical = true;

iglob = zeros(NGLL,NGLL,NELX*NELY);	% local to global index mapping
nglob = (NELX*(NGLL-1)+(~periodical)*1)*(NELY*(NGLL-1)+1);	% number of global nodes
% if periodical
%     nglob = (NELX * (NGLL-1))*(NELY*(NGLL-1)+1);
% end

x     = zeros(nglob,1);		% coordinates of GLL nodes
y     = zeros(nglob,1);	

e=0;
last_iglob = 0;
igL = reshape([1:NGLL*(NGLL-1)],NGLL-1,NGLL);
igB = reshape([1:NGLL*(NGLL-1)],NGLL,NGLL-1);
igLB = reshape([1:(NGLL-1)*(NGLL-1)],NGLL-1,NGLL-1);
xgll = repmat( 0.5*(1+XGLL) , 1,NGLL);
ygll = dye*xgll';
xgll = dxe*xgll;

for ey=1:NELY, 
for ex=1:NELX, 

  e = e+1;
  %easier indexing
  for i = 1:1:NGLL
      for j = 1:1:NGLL
          
          iglob(i,j,e) = ((ey-1) * (NGLL-1) + j-1) * (NELX * (NGLL-1)+ (~periodical)*1);
          if(~periodical)
              xpos = ((ex-1)*(NGLL-1) + i-1)+ 1 ; 
          else
              xpos = mod(((ex-1)*(NGLL-1) + i-1),NELX*(NGLL-1))+1;
          end
          iglob(i,j,e) = iglob(i,j,e) + xpos;
                
            x(iglob(i,j,e)) = dxe*(ex-1)+xgll(i,1);
            y(iglob(i,j,e)) = dye*(ey-1)+ygll(1,j);
      end
  end  
end
end

% for ey=1:NELY, 
% for ex=1:NELX, 
% 
%   e = e+1;
% 
%  % Take care of redundant nodes at element edges :
%   if e==1  % first element: bottom-left
%     ig = reshape([1:NGLL*NGLL],NGLL,NGLL);    
%   else
%     if ey==1 	%  elements on first (bottom) row
%       ig(1,:) = iglob(NGLL,:,e-1); 		% left edge
%       ig(2:NGLL,:) = last_iglob + igL; 		% the rest
%     elseif ex==1 % elements on first (left) column
%       ig(:,1) = iglob(:,NGLL,e-NELX); 		% bottom edge
%       ig(:,2:NGLL) = last_iglob + igB; 		% the rest
%     else 	% other elements
%       ig(1,:) = iglob(NGLL,:,e-1); 		% left edge
%       ig(:,1) = iglob(:,NGLL,e-NELX); 		% bottom edge
%       ig(2:NGLL,2:NGLL) = last_iglob + igLB;
%     end
%   end
%   iglob(:,:,e) = ig;
%   last_iglob = ig(NGLL,NGLL);
% 
%  % Global coordinates of the computational (GLL) nodes
%   x(ig) = dxe*(ex-1)+xgll;
%   y(ig) = dye*(ey-1)+ygll;
% 
%    
% end
% end    

x = x-LX/2;
nglob = length(x);

RHO = 2670;
VS1 = 0.8*3464;  % modified for layer case
VS2 = 3464;
VP1 = 0.8*6000;
VP2 = 6000;
ETA = 0;
THICK = 30;  % Thickness of the first layer with VS1 (m)
            % Make sure THICK is integer multiple of dye 
%------------------------------------------
% STEP 2: INITIALIZATION

% 
[xgll,wgll,H] = GetGLL(NGLL);
Ht = H';
wgll2 = wgll * wgll' ;

W     = zeros(NGLL,NGLL,NEL);	% for internal forces
Wl    = zeros(NGLL,NGLL,NEL);
M     = zeros(nglob,1);		    % global mass matrix, diagonal
rho   = zeros(NGLL,NGLL);	    % density will not be stored
mu    = zeros(NGLL,NGLL);	    % shear modulus will not be stored
muMax = 0;                    % Used for variable time stepping

%**** Set here the parameters of the time solver : ****
%NT = 347;                     % number of timesteps
CFL = 0.3;                     % stability number = CFL_1D / sqrt(2)
%********

dt = Inf;  			% timestep (set later)

% For this simple mesh the global-local coordinate map (x,y)->(xi,eta)
% is linear, its jacobian is constant
dx_dxi  = 0.5*dxe;
dy_deta = 0.5*dye;
jac = dx_dxi*dy_deta;
coefint1 = jac/dx_dxi^2 ;
coefint2 = jac/dy_deta^2 ;

% FOR EACH ELEMENT ...
for ey=1:NELY,
    for ex=1:NELX,

        e = (ey-1)*NELX+ex;
        ig = iglob(:,:,e);
        
        %**** Set here the physical properties of the heterogeneous medium : ****
        if (ey*dye <= -10*THICK)  % modified for layer case
        rho(:,:) = RHO;
        mu(:,:)  = RHO* VS1^2;
        ld(:,:)  = RHO* VP1^2 - 2* mu(:,:);
        else
        rho(:,:) = RHO;
        mu(:,:)  = RHO* VS2^2;   
        ld(:,:)  = RHO* VP2^2 - 2* mu(:,:);
        end
        if muMax < max(max(mu)); muMax = max(max(mu)); end;
        
        %********
        
        % Diagonal mass matrix
        M(ig) = M(ig) + wgll2 .*rho *jac;
        
        % Local contributions to the stiffness matrix K
        %  WX(:,:,e) = wgll2 .* mu *jac/dx_dxi^2;
        %  WY(:,:,e) = wgll2 .* mu *jac/dy_deta^2;
        W(:,:,e) = wgll2 .* mu;
        Wl(:,:,e) = wgll2 .* ld;
        % The timestep dt is set by the stability condition
        % dt = CFL*min(dx/vs)
        vs = sqrt(mu./rho);
        if dxe<dye
            vs = max( vs(1:NGLL-1,:), vs(2:NGLL,:) );
            dx = repmat( diff(xgll)*0.5*dxe ,1,NGLL);
        else
            vs = max( vs(:,1:NGLL-1), vs(:,2:NGLL) );
            dx = repmat( diff(xgll)'*0.5*dye ,NGLL,1);
        end
        dtloc = dx./vs;
        dt = min( [dt dtloc(1:end)] );

    end
end  %... of element loop
dt = CFL*dt;
dtmin = dt;

tmax = Total_time;
dtmax = 50*24*60*60/distN*100; % 5 days

if ETA, dt=dt/sqrt(1+2*ETA); end  % dt modified slightly for damping
NT = ceil(Total_time/dtmin)       % estimate the max possible time step
half_dt = 0.5*dtmin;
half_dt_sq = 0.5*dtmin^2;

%-- Initialize kinematic fields, stored in global arrays
d = zeros(nglob,2);  %xy plane d(:,1) = ux, d(:,2) = uy;
v = zeros(nglob,2);
v(:,1) = 1/2*10^-3;
vPre = zeros(nglob,2);
a = zeros(nglob,2);

Vpl = 2*10^-3/yr2sec;    % imposed loading 2 mm/yr 

%-- Absorbing boundaries (first order):
% Left
ng = NELY*(NGLL-1)+1;
BcLeftIglob = zeros(ng,1);
BcLeftC = zeros(ng,1);
for ey=1:NELY,
    ip = (NGLL-1)*(ey-1)+[1:NGLL] ;
    e = (ey-1)*NELX+1;
    BcLeftIglob(ip) = iglob(1,1:NGLL,e);
    if (ey*dye <= THICK)  % modified for layer case
        impedance = RHO*VS1;
    else
        impedance = RHO*VS2;         
    end
    BcLeftC(ip) = BcLeftC(ip) + dy_deta*wgll*impedance ;
end
% Right
ng = NELY*(NGLL-1)+1;
BcRightIglob = zeros(ng,1);
BcRightC = zeros(ng,1);
for ey=1:NELY,
    ip = (NGLL-1)*(ey-1)+[1:NGLL] ;
    e = (ey-1)*NELX+NELX;
    BcRightIglob(ip) = iglob(NGLL,1:NGLL,e);
    if (ey*dye <= THICK)  % modified for layer case
        impedance = RHO*VS1;
    else
        impedance = RHO*VS2;         
    end
    BcRightC(ip) = BcRightC(ip) + dy_deta*wgll*impedance ;
end
% Top
ng = NELX*(NGLL-1)+1;
BcTopIglob = zeros(ng,1);
BcTopCx = zeros(ng,1);
BcTopCz = zeros(ng,1);
for ex=1:NELX,
    ip = (NGLL-1)*(ex-1)+[1:NGLL] ;
    e = (NELY-1)*NELX+ex;
    BcTopIglob(ip) = iglob(1:NGLL,NGLL,e);
%    if (ex < NELX/2)          % modified for layer case   
%    impedance = RHO*VS1;
%    else
    impedance = RHO*VS2;
%    end
    BcTopCx(ip) = BcTopCx(ip) + dx_dxi*wgll*impedance ;
    BcTopCz(ip) = BcTopCz(ip) + dx_dxi*wgll*impedance;
end

Mq = M;
% % The mass matrix needs to be modified at the boundary
% % for the IMPLICIT treatment of the term C*v.
% Fortunately C is diagonal.
%M(BcLeftIglob)  = M(BcLeftIglob)  +half_dt*BcLeftC;
%M(BcRightIglob) = M(BcRightIglob) +half_dt*BcRightC;
Mx = M;
Mz = M;
Mx(BcTopIglob) = Mx(BcTopIglob) + half_dt*BcTopCx;
Mz(BcTopIglob) = Mz(BcTopIglob) + half_dt*BcTopCz;

%-- DYNAMIC FAULT at bottom boundary
FaultNglob = NELX*(NGLL-1)+1;
FaultIglob = zeros(FaultNglob,1);
FaultB = zeros(FaultNglob,1);
for ex = 1:NELX,
    ip = (NGLL-1)*(ex-1)+[1:NGLL];
    e = ex;
    FaultIglob(ip) = iglob(1:NGLL,1,e);
    FaultB(ip) = FaultB(ip) + dx_dxi*wgll;    
end
%FaultZ = M(FaultIglob)./FaultB /half_dt;
if(periodical)  %periodical boundary condition
    FaultB(1) = FaultB(1) + FaultB(end);
    FaultB = FaultB(1:end-1);
    FaultIglob = FaultIglob(1:end-1);
    FaultNglob = FaultNglob-1;
end
FaultZ = M(FaultIglob)./FaultB /half_dt * 0.5;  % times 0.5 due to the symmetry
FaultX = x(FaultIglob);

Seff = repmat(120*10^6,FaultNglob,1);  % effective normal stress
fo = repmat(0.6,FaultNglob,1);         % reference friction
cca = repmat(0.0144,FaultNglob,1);      % constitutive parameter a
ccb = repmat(0.0191,FaultNglob,1);      % constitutive parameter b
Vo = repmat(10^-6,FaultNglob,1);       % reference velocity Vo
xLf = repmat(2*0.042/distN,FaultNglob,1);      % L (D_c) = 84 um
FaultC = repmat(0,FaultNglob,1);       % used only for integrated state variable 
Vf1 = repmat(0,FaultNglob,1);
Vf2 = repmat(0,FaultNglob,1);
Vf  = repmat(0,FaultNglob,1);
psi1 = repmat(0,FaultNglob,1);
psi2 = repmat(0,FaultNglob,1);
tau1 = repmat(0,FaultNglob,1);
tau2 = repmat(0,FaultNglob,1);
tau3 = repmat(0,FaultNglob,1);
tauNR = repmat(0,FaultNglob,1);
tauAB = repmat(0,FaultNglob,1);         % USED FOR QUASISTATIC

if IDintitCond == 1
     
      
elseif IDintitCond == 2
    xshift = 10;
    xcoord = FaultX-xshift;
    %-- Initial conditions smooth in time and space
    tauoBack = 70*10^6;
    tauo = repmat(tauoBack,FaultNglob,1);
    width = 2*3e3/distN;
    isel = find(abs(xcoord)<=width/2);
    Peaktauo = 81.6*10^6;
    Amplitude = (Peaktauo-tauoBack)/2;
    tauo(isel) = (Peaktauo+tauoBack)/2 ...
        + Amplitude*cos(2*pi*(xcoord(isel))/width);
    isel2 = find(abs(xcoord)>10e3/distN);
    
    ccbOut = 0.0097;
    ccbIn = 0.0191; 
    
    ccb(isel2) = ccbOut;
    Amplitude2 = (ccbIn + ccbOut)/2;
    Amplitude3 = (ccbIn - ccbOut)/2;
    isel3 = find(xcoord>=8e3/distN&xcoord<=(8e3/distN+width/2));
    ccb(isel3)=Amplitude2 + Amplitude3*cos(2*pi*(xcoord(isel3)-8e3)/width);
    isel4 = find(xcoord<=-8e3/distN&xcoord>=-(8e3/distN+width/2));
    ccb(isel4)=Amplitude2 + Amplitude3*cos(2*pi*(xcoord(isel4)+8e3)/width);
    tau = repmat(0,FaultNglob,1);
    psi = tauo./(Seff.*ccb) - fo./ccb - (cca./ccb).*log(2*v(FaultIglob)./Vo);
    psi0 = psi;

end

%d = d_store;
%v = v_store;
%psi = psi_store;
%psi0 = psi;

if ETA,  % Kelvin-Voigt viscosity
  %NEL_ETA = min( NELX, ceil(L_BARRIER/dxe)+2 );
  NEL_ETA = NELX;
  x1 = 0.5*(1+xgll');
  eta_taper = exp(-pi*x1.^2); 
  eta = ETA*dt *repmat(eta_taper, NGLL,1 );
else
  NEL_ETA = 0;
end

%-- initialize data for output seismograms
%**** Set here receiver locations : ****
OUTxseis = [-15:3:0]';     		    % x coord of receivers
OUTnseis = length(OUTxseis);		% total number of receivers
OUTyseis = repmat(15,OUTnseis,1);	% y coord of receivers
%********
%receivers are relocated to the nearest node
%OUTdseis = distance between requested and relocated receivers
[OUTxseis,OUTyseis,OUTiglob,OUTdseis] = FindNearestNode(OUTxseis,OUTyseis,x,y);
kkseis=1;
%OUTv = zeros(OUTnseis,NT);

%-- initialize data for output snapshots
OUTindx = Init2dSnapshot(iglob);

% time is a array stored time at each time step
t = 0;
it = 0;
dtincf = 1.2;
dtpre = dt;
gamma = pi/4;
% average node spacing
hcell = LX/(FaultNglob-1);
Ximax = 0.5;   % value from NL00 (15ab)
Xithf = 1;
trec = 0;
Vthres = 0.01;  % 1 cm/s
slipstart = 0;
ievb = 0;
ieva = 0;
ntvsx=0;
tvsx = 0.5*yr2sec;
tvsxinc = tvsx;
nevne = 0;
tevneinc = 0.001;
Vevne = Vthres;

% compute XiLf for each fault node
for j=1:FaultNglob
    % Compute time-restricting parameters as in section 4, NL00
    expr1=-(cca(j) - ccb(j))/cca(j);
    expr2=gamma*muMax/hcell*xLf(j)/(cca(j)*Seff(j));
    ro=expr2-expr1;
    if (0.25*ro*ro-expr2) >= 0 
        Xith(j)=1/ro;
    else    
        Xith(j)=1-expr1/expr2;
    end 
    % For each node, compute the slip that the node cannot
    % exceed in one time step; store in array XiLf(FaultNglob)
    if (Xithf*Xith(j) > Ximax) 
        XiLf(j)=Ximax*xLf(j);
    else
        XiLf(j)=Xithf*Xith(j)*xLf(j);
    end    
end

% time-related variables added
OUTt = 0.5;
q = 1;
OUTtGo = 0;
OUTtCount = 1;

% OUTPUT field quantities at several locations on fault
OutLoc1 = 0e3/distN;                % 0 km point
[OUTxLoc1,OUTyLoc1,OUTiglobLoc1] = FindNearestNode(OutLoc1,0,x,y);
FaultLoc1 = round((OutLoc1+LX/2)*FaultNglob/LX);

OutLoc2 = 3e3/distN;                % 3 km point
[OUTxLoc2,OUTyLoc2,OUTiglobLoc2] = FindNearestNode(OutLoc2,0,x,y);
FaultLoc2 = round((OutLoc2+LX/2)*FaultNglob/LX);

OutLoc3 = 6e3/distN;                % 6 km point
[OUTxLoc3,OUTyLoc3,OUTiglobLoc3] = FindNearestNode(OutLoc3,0,x,y);
FaultLoc3 = round((OutLoc3+LX/2)*FaultNglob/LX);

OutLoc4 = 9e3/distN;                % 9 km point
[OUTxLoc4,OUTyLoc4,OUTiglobLoc4] = FindNearestNode(OutLoc4,0,x,y);
FaultLoc4 = round((OutLoc4+LX/2)*FaultNglob/LX);

% center of model domain              
[OUTxLoc5,OUTyLoc5,OUTiglobLoc5] = FindNearestNode(0,30,x,y);

disp('Total number of nodes on fault = ');
disp(num2str(FaultNglob));
disp('Average node spacing = ');
disp(LX/1000/(FaultNglob-1));

fprintf('dt = %1.17f \n',dt);
pp = 1;

jj = 1;
jjj = 1;
for ii = 1:nglob
    if ii == FaultIglob(jj)
        jj = jj + 1; 
        if jj > length(FaultIglob)
            jj = length(FaultIglob);
        end
    else
       FaultNIglob(jjj,1) = ii;  % find nodes that do not belong to fault
       jjj = jjj + 1; 
    end
end

r = zeros(nglob,2);	
beta = zeros(nglob,1);	
alpha = zeros(nglob,1);	
p = zeros(nglob,2);	
F = zeros(nglob,2);	
dPre = zeros(nglob,2);
vPre = zeros(nglob,2);
dd = zeros(nglob,2);
dacum = zeros(nglob,2);

dnew = zeros(length(FaultNIglob),2);	
Fnew = zeros(length(FaultNIglob),2);	
anew = zeros(length(FaultNIglob),2);	
rnew = zeros(length(FaultNIglob),2);	
pnew = zeros(length(FaultNIglob),2);	 

%------------------------------------------
% STEP 3: SOLVER  M*a = -K*d +F
% Explicit Newmark scheme with
% alpha=1, beta=0, gamma=1/2
%
isolver = 1;   % initially, 1 for quasistatic, 2 for dynamic
go_snap = 0;
go_snapDY = 0;

% compute the diagonal of K
Kdiagx = zeros(nglob,1);	
Kdiagz = zeros(nglob,1);
Kdiag = zeros(nglob,2);

Klocdiagx = zeros(NGLL,NGLL);
Klocdiagz = zeros(NGLL,NGLL);

for e=1:NEL, % FOR EACH ELEMENT ...
    ig = iglob(:,:,e);
    wloc = W(:,:,e);
    wlloc = Wl(:,:,e);
    Klocdiagx(:,:) = 0;
    Klocdiagz(:,:) = 0;

    for k = 1:NGLL
        for j = 1:NGLL
            Klocdiagx(k,j)=Klocdiagx(k,j)+sum(coefint1*H(k,:)'.*(wlloc(:,j)+2*wloc(:,j)).*Ht(:,k)...
                    +coefint2*(wloc(k,:).*H(j,:))'.*Ht(:,j));
            Klocdiagz(k,j)=Klocdiagz(k,j)+sum(coefint1*H(k,:)'.*(wlloc(:,j)).*Ht(:,k)...
                    +coefint2*((2*wloc(k,:)+wlloc(k,:)).*H(j,:))'.*Ht(:,j));
        end
    end
    Kdiagx(ig) = Kdiagx(ig) + Klocdiagx(:,:);
    Kdiagz(ig) = Kdiagz(ig) + Klocdiagz(:,:);
end

Kdiag(:,1) = Kdiagx;
Kdiag(:,2) = Kdiagz;
diagKnew = Kdiag(FaultNIglob,:);

v(:,1) = v(:,1) - 0.5*Vpl;
Vf = 2*v(FaultIglob,:);
iFBC = find(abs(FaultX)>=bound*10^3/distN);
NFBC = length(iFBC);
Vf(iFBC,:) = 0;

jj = 1;
FaultIglobBC = zeros(NFBC,1);
for ex = 1:NELX
    for k = 1:NGLL
       if abs(x(iglob(k,1,ex))) >= bound*10^3/distN 
          FaultIglobBC(jj) = iglob(k,1,ex);
          jj = jj + 1;
       end
    end        
end
v(FaultIglobBC,:) = 0;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%% START OF TIME LOOP %%%%%%%%%%%%%%%%%%%%%%%%%

end

if restart
    v = v_store;
    d = d_store;
    a = a_store;
    psi=psi_store;
    [dt]=dtevol(0.1,dtmax,dtmin,dtincf,XiLf,FaultNglob,NFBC,2*v(FaultIglob)+Vpl,isolver);
end
[dt]=dtevol(0.001,dtmax,dtmin,dtincf,XiLf,FaultNglob,NFBC,2*v(FaultIglob)+Vpl,isolver);

while t < tmax,
    dt
    it = it + 1;
    t = t + dt;
    time(it) = t;
    
        v_store = v;
        d_store = d;
        a_store = a;
        psi_store=psi;
        dt_store = dt;
   
    if isolver == 1
    
    %if true
    display('quasi solver');
    
    vPre = v;
    dPre = d;
    
    Vf0 = 2*v(FaultIglob,1) + Vpl;
    Vf = Vf0;
    
    for p1=1:2
    
    % compute the forcing term F
    F(:,:) = 0;
    F(FaultIglob,:) = dPre(FaultIglob,:) + v(FaultIglob,:)*dt;
    
    % assign previous solution of the disp field as an initial guess
    dnew = d(FaultNIglob,:);
    

    [dnew,n1(p1)]=myPCGnew3(coefint1,coefint2,diagKnew,dnew,F,FaultIglob,...
        FaultNIglob,H,Ht,iglob,NEL,nglob,W,Wl,x,y);
    
   
    % update displacement of medium
    d(FaultNIglob,:) = dnew;
    
    % make d = F on the fault
    d(FaultIglob,:) = F(FaultIglob,:);
    
    % compute on-fault stress  
    a = computeforce(iglob,W,Wl,H,Ht,d,coefint1, coefint2);

    a(FaultIglobBC,:) = 0;  % enforce K*d for velocity boundary (v = 0) to be zero.
    tau1 = -a(FaultIglob,:)./(FaultB);   
    
    % compute slip rates on fault
    for jF=1:FaultNglob
        j = jF ;
        if IDstate == 1
            psi1(j) = psi(j) + dt*((Vo(j)./xLf(j)).*exp(-psi(j)) - abs(Vf(j))./xLf(j));    
        elseif IDstate == 2
            % compute psi(t+dt) = psi0 + ln(1+FaultC(t+dt)) - FaultD/L
            VdtL = abs(Vf(j))*dt/xLf(j);
            if VdtL < 10^-6
                psi1(j) = log(exp(psi(j)-VdtL) + ...
                    Vo(j)*dt/xLf(j)-0.5*Vo(j)*abs(Vf(j))*dt*dt/(xLf(j)*xLf(j)));
            else
                psi1(j) = log(exp(psi(j)-VdtL) + ...
                    (Vo(j)/abs(Vf(j)))*(1-exp(-VdtL)));
            end            
        elseif IDstate == 3
            psi1(j) = exp(-abs(Vf(j)).*dt./xLf(j)).*log(abs(Vf(j))./Vo(j)) + ...
                exp(-abs(Vf(j)).*dt./xLf(j)).*psi(j) + log(Vo(j)./abs(Vf(j)));
            if ~any(imag(psi1(j))) == 0
                return
            end
        end
        tauAB(j) = tau1(j) + tauo(j);
        fa = tauAB(j)/(Seff(j)*cca(j));
        help = -(fo(j)+ccb(j)*psi1(j))/cca(j);
        help1 = exp(help+fa);
        help2 = exp(help-fa);
        Vf1(j) = Vo(j)*(help1 - help2);     
    end
    Vf1(iFBC) = Vpl;
    Vf = (Vf0+Vf1)/2;
    v(FaultIglob) = 0.5*Vf-0.5*Vpl;
    
    end
    %[n1(1) n1(2)]
    psi = psi1;
    tau = tau1;
    tau(iFBC) = 0;
    Vf1(iFBC) = Vpl;
    
    v(FaultIglob) = 0.5*Vf1-0.5*Vpl;
    v(FaultNIglob) = (d(FaultNIglob)-dPre(FaultNIglob))/dt;
    
    RHS = a;
    RHS(FaultIglob,:) = RHS(FaultIglob,:) - FaultB.*tau;    
    RMS = sqrt(sum((RHS(:)).^2)/length(RHS(:)))./max(abs(RHS(:)));
    
    aeff = (v(FaultIglob,:) - vPre(FaultIglob,:))./dt;
    Maeff = [Mq(FaultIglob),Mq(FaultIglob)].*aeff;
    
    %% P_Ma based on max
    P_Ma(it)=max(max(max(abs(Maeff)./abs(a(FaultIglob)))),max(max(abs(Maeff)./(abs(FaultB.*tau)))));
   
    a(:,:) = 0;
    
    d(FaultIglobBC,:) = 0;
    v(FaultIglobBC,:) = 0;
  
    %hold on
    else  %%%%%%%%%%%%%%%% if max slip rate < 10^-2 m/s %%%%%%%%%%%%%%%%%%% 
    display('Dynamic solver');
    dPre = d;
    vPre = v;
    
    % update
    d = d + dt*v + half_dt_sq*a;
    
    % prediction
    v = v + half_dt*a;
    NGLOB = length(d);
    NEL =length(iglob);
    a=zeros(NGLOB,2);
    ax = zeros(NGLOB,1);
    az = zeros(NGLOB,1);

    % internal forces -K*d(t+1)
    % stored in global array 'a'
    for e=1:NEL,               
        %switch to local (element) representation
        ig = iglob(:,:,e);
        dx = d(:,1);
        dz = d(:,2);
        vx = v(:,1);
        vz = v(:,2);
        isETA = e<=NEL_ETA;
        if isETA
            local_x = dx(ig) +eta.*vx(ig); % Kelvin-Voigt viscosity
            local_z = dz(ig) +eta.*vz(ig);
        else
            local_x = dx(ig) + 0.1*dt*vx(ig); % Kelvin-Voigt viscosity
            local_z = dz(ig) + 0.1*dt*vz(ig);
        end
        %gradients wrt local variables (xi,eta)
    %    d_xi  = Ht*local;
    %    d_eta = local*H;
        %element contribution to internal forces
        %local = coefint1*H*( W(:,:,e).*d_xi ) + coefint2*( W(:,:,e).*d_eta )*Ht ;
        wloc = W(:,:,e);
        wlloc = Wl(:,:,e);
        
        dxxxx = H * ( (wloc + 2*wlloc) .* (Ht*local_x)) * coefint1; 
        dzzzz = ((wloc + 2*wlloc) .* (local_z*H)) * Ht * coefint2;
        dxxzz = H * (wlloc .* (local_z*H)); 
        dzzxx = (wlloc .* (Ht*local_x)) * Ht;
        
        dxzxz = (wloc .* (local_x*H)) * Ht * coefint2;
        dxzzx = (wloc .* (Ht*local_z)) * Ht;
        dzxxz = H * (wloc .* (local_x*H));
        dzxzx = H * (wloc .* (Ht*local_z)) * coefint1;
        
        
        local_x = dxxxx + dxxzz + dxzxz + dxzzx;
        local_z = dzzzz + dzzxx + dzxzx + dzxxz;
        
        %assemble into global vector
        ax(ig) = ax(ig) - local_x;
        az(ig) = az(ig) - local_z;
    end
    a(:,1) = ax;
    a(:,2) = az;
    a(FaultIglobBC,:) = 0;  % enforce K*d for velocity boundary (v = 0) to be zero.
    
    % absorbing boundaries:
%   a(BcLeftIglob)  = a(BcLeftIglob)  - BcLeftC  .* v(BcLeftIglob);
%    a(BcRightIglob) = a(BcRightIglob) - BcRightC .* v(BcRightIglob);
    a(BcTopIglob,1)   = a(BcTopIglob,1)   - BcTopCx   .* v(BcTopIglob,1);
    a(BcTopIglob,2)   = a(BcTopIglob,2)   - BcTopCz   .* v(BcTopIglob,2);

    %%%%%%%%%%% fault boundary condition: rate-state friction %%%%%%%%%%%%
    
    FaultVFree = 2*v(FaultIglob,:) + 2*half_dt*a(FaultIglob,:)./M(FaultIglob);   % times 2 due to the symmetry;
    
    % compute state variable using Vf from the previous time step
    Vf = 2*vPre(FaultIglob,1) + Vpl;

    for jF=1:FaultNglob-NFBC
        j = jF + NFBC/2;
        if IDstate == 1
            psi1(j) = psi(j) + dt*((Vo(j)./xLf(j)).*exp(-psi(j)) - abs(Vf(j))./xLf(j));
            
        elseif IDstate == 2
            % compute psi(t+dt) = psi0 + ln(1+FaultC(t+dt)) - FaultD/L
            if (abs(Vf(j))*dt/xLf(j)) < 10^-5
                psi1(j) = log(exp(psi(j)-abs(Vf(j))*dt/xLf(j)) + ...
                    Vo(j)*dt/xLf(j)-0.5*Vo(j)*abs(Vf(j))*dt*dt/(xLf(j)*xLf(j)));
            else
                psi1(j) = log(exp(psi(j)-abs(Vf(j))*dt/xLf(j)) + ...
                    (Vo(j)/abs(Vf(j)))*(1-exp(-abs(Vf(j))*dt/xLf(j))));
            end
        elseif IDstate == 3
            psi1(j) = exp(-abs(Vf(j)).*dt./xLf(j)).*log(abs(Vf(j))./Vo(j)) + ...
                exp(-abs(Vf(j)).*dt./xLf(j)).*psi(j) + log(Vo(j)./abs(Vf(j)));
            if ~any(imag(psi1(j))) == 0
                return
            end
        end
     
        % N-R search
        tauNR(j) = tau(j) + tauo(j);
        [Vf1(j),tau1(j)]=NRsearch_NEW(fo(j),Vo(j),cca(j),ccb(j),Seff(j),...
            tauNR(j),tauo(j),psi1(j),FaultZ(j),FaultVFree(j,1));
        if Vf(j) > 10^10 || isnan(Vf(j)) == 1 || isnan(tau1(j)) == 1 
            'NR search failed!'
            return
        end
            
        if IDstate == 1
            psi2(j) = psi(j) + 0.5*dt*( ((Vo(j)/xLf(j))*exp(-psi(j)) - abs(Vf(j))/xLf(j))...
                +((Vo(j)/xLf(j))*exp(-psi1(j)) - abs(Vf1(j))/xLf(j)) );            
        elseif IDstate == 2
            if (0.5*abs(Vf1(j)+Vf(j))*dt/xLf(j)) < 10^-6
                psi2(j) = log(exp(psi(j)-0.5*abs(Vf1(j)+Vf(j))*dt/xLf(j)) + ...
                    Vo(j)*dt/xLf(j)-0.5*Vo(j)*0.5*abs(Vf1(j)+Vf(j))*dt*dt/(xLf(j)*xLf(j)));
            else
                psi2(j) = log(exp(psi(j)-0.5*abs(Vf1(j)+Vf(j))*dt/xLf(j)) + ...
                    (Vo(j)/(0.5*abs(Vf1(j)+Vf(j))))*(1-exp(-0.5*abs(Vf1(j)+Vf(j))*dt/xLf(j))));
            end
        elseif IDstate == 3
            psi2(j) = exp(-0.5*abs(Vf1(j)+Vf(j)).*dt./xLf(j)).*log(0.5*abs(Vf1(j)+Vf(j))./Vo(j)) + ...
                exp(-0.5*abs(Vf1(j)+Vf(j)).*dt./xLf(j)).*psi(j) + log(Vo(j)./(0.5*abs(Vf1(j)+Vf(j))));
        end
        % N-R search (2nd loop)
        [Vf2(j),tau2(j)]=NRsearch_NEW(fo(j),Vo(j),cca(j),ccb(j),Seff(j),...
            tau1(j),tauo(j),psi2(j),FaultZ(j),FaultVFree(j));

    end
    
    tau = tau2 - tauo;
    tau(iFBC) = 0;
    psi = psi2;
    KD = a;
    a(FaultIglob,1) = a(FaultIglob,1) - FaultB .*tau;
    
    %%%%%%%%%%%%%%%%%% the end of fault boundary condition %%%%%%%%%%%%%%%%
    RHS = a;
    
    % solve for a_new:
    a = a ./[Mx,Mz] ;

    % correction
    v = v + half_dt*a;
    
    v(FaultIglobBC,1) = 0;
    a(FaultIglobBC,1) = 0;
    
    %% P_Ma based on max
    P_Ma(it)=max(max(abs(M(FaultIglob).*a(FaultIglob))./abs(KD(FaultIglob))),max(abs(M(FaultIglob).*a(FaultIglob))./abs(FaultB.*tau)));  
    
    % compute residual
    LHS = M.*a;  
    RMS = sqrt(sum((RHS-LHS).^2)/length(RHS))./max(abs(RHS));
    
    end
    
    if(isolver==1)
        everyN = 1;
    else
        everyN = 100;
    end
    
    if(mod(it,everyN) == 0)
        if(isolver==1)
            c = 'b';
        else
            c = 'r';
        end
        figure(1);

        subplot(2,1,1);
        scatter(x,y,10,v(:,1),'fill');
        colormap('jet');
        subplot(2,1,2);
        scatter(x,y,10,v(:,2),'fill');
        colormap('jet');
        getframe;
        figure(2);
        A = [2:length(FaultIglob),1];
        plot([x(FaultIglob(A));x(FaultIglob(A))+90],[log10(v(FaultIglob(A)));log10(v(FaultIglob(A)))],c);
        getframe;
        hold on
        figure(3);
        plot(x(FaultIglob(A)),(psi(A)),c);
        getframe;
        hold on
    end
    
    Vfmax=2*max(v(FaultIglob))+Vpl;  % compute Vfmax used a lot in OUTPUT
        
    % Output variables at 0km, 3km, 6km and 9km for every time step
    Vloc1(it) = 2*v(OUTiglobLoc1) + Vpl;
    Vloc2(it) = 2*v(OUTiglobLoc2) + Vpl;
    Vloc3(it) = 2*v(OUTiglobLoc3) + Vpl;
    Vloc4(it) = 2*v(OUTiglobLoc4) + Vpl;
    VmaxSave(it) = Vfmax;
    Dloc1(it) = 2*d(OUTiglobLoc1) + Vpl * t;
    Dloc2(it) = 2*d(OUTiglobLoc2) + Vpl * t;
    Dloc3(it) = 2*d(OUTiglobLoc3) + Vpl * t;
    Dloc4(it) = 2*d(OUTiglobLoc4) + Vpl * t;
    Tauloc1(it) = (tau(FaultLoc1)+tauo(FaultLoc1))/10^6;
    Tauloc2(it) = (tau(FaultLoc2)+tauo(FaultLoc2))/10^6;
    Tauloc3(it) = (tau(FaultLoc3)+tauo(FaultLoc3))/10^6;
    Tauloc4(it) = (tau(FaultLoc4)+tauo(FaultLoc4))/10^6;
    dtSave(it) = dt;
    if (isolver == 1); NumIteSave(it) = n1(1)+n1(2); end;
    d5(it) = d(OUTiglobLoc5);
    v5(it) = v(OUTiglobLoc5);
    a5(it) = a(OUTiglobLoc5);
    
%     if (mod(it,10) == 0 && isolver == 1)
%        figure(10);
%        plot(FaultX,Vf2);    
%     end
% 
%     if mod(it,100) == 0 
%         figure(3)
%         Plot2dSnapshot(x,y,v,OUTindx,[0 1]);
%     end
       
%     if (t > 6*yr2sec && Vfmax > 0.2 && go_snapDY == 0) || (go_snapDY > 0 && t > t_snapDY + 1/distN)
%         figure(31 + go_snapDY);
%         Plot2dSnapshot(x,y,v,OUTindx,[0 1]);
%         colorbar;        
%         file1 = sprintf('SnapQSVel%u.dat',go_snapDY);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);        
%         t_snapDY = t;
%         go_snapDY = go_snapDY + 1;        
%         if go_snapDY > 9
%             go_snapDY = -1;
%         end
%     end     
%     
%     if t > (tevent-5*yr2sec) && go_snap == 0;  % 5 year before 
%         figure(21);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 1;        
%     end
%     if t > (tevent-1*yr2sec) && go_snap == 1;  % 1 year before 
%         figure(22);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 2;    
%     end
%     if t > (tevent-24*60*60) && go_snap == 2;  % 1 day before 
%         figure(23);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 3;    
%     end
%     if t > (tevent-60*60) && go_snap == 3;     % 1 hour before     
%         figure(24);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 4;    
%     end
%     if t > (tevent-60) && go_snap == 4;        % 1 min before     
%         figure(25);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 5;    
%     end
%     if t > (tevent+60) && go_snap == 5;        % 1 min after  
%         figure(26);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 6;    
%     end    
%     if t > (tevent+60*60) && go_snap == 6;     % 1 hour after
%         figure(27);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 7;    
%     end  
%     if t > (tevent+24*60*60) && go_snap == 7;  % 1 day after
%         figure(28);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 8;                         
%     end  
%     if t > (tevent+1*yr2sec) && go_snap == 8;  % 1 year after
%         figure(29);
%         %Plot2dSnapshot(x,y,d*distN,OUTindx,[min(min(d*distN)) max(max(d*distN))]);
%         Plot2dSnapshot(x,y,v,OUTindx,[min(min(v)) max(max(v))]);
%         colorbar;
%         file1 = sprintf('SnapQSVelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(v)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), v(ii));
%         end
%         fclose(fid);
%         file1 = sprintf('SnapQSDelint%u.dat',go_snap);
%         fid = fopen(file1,'w');
%         for ii=1:length(d)
%            fprintf(fid,'%14.6e%14.6e%14.6e\n', y(ii), x(ii), d(ii));
%         end
%         fclose(fid);
%         go_snap = 9;    
%     end  
    
    %OUTPUT stress, slip, and slip velocity on fault every certain interval
    if (t>tvsx)        % "delvsx"
        ntvsx=ntvsx+1;
        delf5yr(:,ntvsx) = 2*d(FaultIglob)+Vpl*t;
        Vf5yr(:,ntvsx) = 2*v(FaultIglob)+Vpl;
        Tau5yr(:,ntvsx) = (tau + tauo)/10^6;
        tvsx = tvsx + tvsxinc;
    end
    if (Vfmax>Vevne && false)    %"delevne"
         if (idelevne==0)
            nevne=nevne+1;
            idelevne = 1;
            tevneb = t;
            tevne = tevneinc;
            delfsec(:,nevne)=2*d(FaultIglob)+Vpl*t;
            Vfsec(:,nevne) = 2*v(FaultIglob)+Vpl;
            Tausec(:,nevne) = (tau + tauo)/10^6;
         end
         if (idelevne==1 && (t-tevneb)>tevne) 
            nevne=nevne+1;
            delfsec(:,nevne)=2*d(FaultIglob)+Vpl*t;
            Vfsec(:,nevne) = 2*v(FaultIglob)+Vpl;
            Tausec(:,nevne) = (tau + tauo)/10^6;
            tevne = tevne + tevneinc;
         end
    else
        idelevne = 0;
    end
      
    %OUTPUT stress and slip before and after events
%     if (Vfmax > 1.01*Vthres && slipstart == 0) 
%         ievb=ievb+1;
%         delfref = 2*d(FaultIglob)+Vpl*t;
%         taubefore(:,ievb) = (tau + tauo)/10^6;
%         tevStart(ievb) = t;
%         slipstart = 1;
%     end
%     if (Vfmax < 0.99*Vthres && slipstart == 1)
%         ieva=ieva+1;
%         tauafter(:,ieva) = (tau + tauo)/10^6;
%         delfafter(:,ieva) = 2*d(FaultIglob)+Vpl*t - delfref;
%         tevStop(ieva) = t;
%         slipstart = 0;
%     end
    
    %OUTPUT time step info on screen
    if mod(it,20) == 0
        fprintf('it = %5d \n',it); 
        fprintf('dt (s) = %1.4g \n',dt);
        fprintf('t (yr) = %1.5g \n',t/yr2sec);
        fprintf('Vmax (m/s) = %1.4g \n',Vfmax);
        fprintf('vmax (m/s) = %1.4g \n',max(v));
        %fprintf('Ma/min(Kd,Btau) = %1.4g \n',P_Ma(it));
        %if isolver == 1
        %    fprintf('n1 = %5d \n',n1(1));
        %    fprintf('n2 = %5d \n',n1(2));
        %    fprintf('RMS (m/s) = %1.3g \n',RMS);
        %end
    end
    
    % Determine quasi-static or dynamic regime based on max slip velocity
    if (isolver == 1 && Vfmax < 5*10^-3) || ...
            (isolver == 2 && Vfmax < 2*10^-3)
       isolver = 1;
    else
       isolver = 2;
    end
    
    % compute next time step dt
    [dt]=dtevol(dt,dtmax,dtmin,dtincf,XiLf,FaultNglob,NFBC,2*v(FaultIglob)+Vpl,isolver);
    
end % ... of time loop

%%%%%%%%%%%%%%%%%%%%%%%% Saving the information %%%%%%%%%%%%%%%%%%%%%%%%
save(['data_SEM2D_QSDY8_SMALL_' st_node_space '.mat'],...
      'FaultX','tauo','Seff','xLf','cca','ccb',...
      'time','Vloc1','Vloc2','Vloc3','Vloc4','VmaxSave',...
      'Dloc1','Dloc2','Dloc3','Dloc4',...
      'Tauloc1','Tauloc2','Tauloc3','Tauloc4',...
      'taubefore','tauafter','delfafter','tevStart','tevStop',...
      'delf5yr','Vf5yr','Tau5yr','delfsec','Vfsec','Tausec',...
      'dtSave','NumIteSave','P_Ma');

