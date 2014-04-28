#include <algorithm>
#include <iostream>
#include <fstream>
#include <sstream>
#include <utility>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>
#include <cmath>
//#include <map>
#include <ctime>
#include <cuda.h>
#include <math_functions.h>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <Windows.h>
#include <MMSystem.h>
#pragma comment(lib, "winmm.lib")
#define _CRTDBG_MAP_ALLOC
#include <crtdbg.h>
using namespace std;

#define _DTH cudaMemcpyDeviceToHost
#define _DTD cudaMemcpyDeviceToDevice
#define _HTD cudaMemcpyHostToDevice
#define THREADS_SMALL 64
#define THREADS_LARGE 256

bool InitMMTimer(UINT wTimerRes);
void DestroyMMTimer(UINT wTimerRes, bool init);
inline int choose2(int n){return n>0 ? ((n*(n-1))>>1):0;}

double CPU_version(double *DP0, double *DP1, const int N){
	double ret=0.;
	const unsigned int adj=N+2;
	memset(DP0,0,adj*adj*sizeof(double));
	DP0[adj]=1.;

	for(int i=0;i<N;i++){//steps taken forward towards N
		if(i&1)memset(DP0,0,adj*adj*sizeof(double));
		else
			memset(DP1,0,adj*adj*sizeof(double));
		for(int j=1;j<=(i+1);j++){//some length amount which could have been reached this turn(length)
			double t;
			for(int k=0;k<j;k++){//k represents the current postions
				if(i&1){
					t=DP1[j*adj+k];//where may have been 1 step back,j index is current length, k is current location
					if(t>0.){//was reached before
						t*=0.5;
						if(0==k)DP0[(j+1)*adj]+=t;//fill in new boundray for next iter
						else
							DP0[j*adj+(k-1)]+=t;//to left
						if((j-1)==k)DP0[(j+1)*adj+j]+=t;//fill in new boundray for next iter
						else
							DP0[j*adj+(k+1)]+=t;//to right
					}
				}else{
					t=DP0[j*adj+k];
					if(t>0.){
						t*=0.5;
						if(0==k)DP1[(j+1)*adj]+=t;
						else
							DP1[j*adj+(k-1)]+=t;
						if((j-1)==k)DP1[(j+1)*adj+j]+=t;
						else
							DP1[j*adj+(k+1)]+=t;
					}
				}
			}
		}
	}
	for(int i=1;i<=(N+1);i++){
		for(int j=0;j<i;j++){
			if(!(N&1))ret+=double(i)*DP0[i*adj+j];
			else
				ret+=double(i)*DP1[i*adj+j];
		}
	}

	return ret;
}

__device__ double atomicAdd(double* address, double val){
    unsigned long long int* address_as_ull =
                              (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;
    do{
        assumed = old;
        old = atomicCAS(address_as_ull, assumed,
                        __double_as_longlong(val +
                               __longlong_as_double(assumed)));
    }while(assumed != old);
    return __longlong_as_double(old);
}

__device__ __forceinline__ int d_choose2(int n){return n>0 ? ((n*(n-1))>>1):0;}
__device__ __forceinline__ int d_num_combo(int a, int b){return a>b ? (d_choose2(a)+b):(d_choose2(b)+a);}

__device__  __forceinline__ double shfl_d64(double x,int lane){
	return __hiloint2double( __shfl( __double2hiint(x), lane ), __shfl( __double2loint(x), lane ));
}

__global__ void GPU_step0(const int i,const double* __restrict__ DP_prev, double* __restrict__ DP_cur, const int adj,const int N){
	const int j=threadIdx.x+blockIdx.x*blockDim.x;
	const int k=blockIdx.y;
	if(j>(i+1) || (k>=j) )return;
	double t= DP_prev[j*adj+k];
	if(t>0.){
		t*=0.5;
		if(0==k)atomicAdd(&DP_cur[(j+1)*adj],t);
		else
			atomicAdd(&DP_cur[j*adj+(k-1)],t);
		if((j-1)==k)atomicAdd(&DP_cur[(j+1)*adj+j],t);
		else
			atomicAdd(&DP_cur[j*adj+(k+1)],t);
	}
}

__global__ void GPU_step1(const double* __restrict__ DP,double* __restrict__ D_ans, const int adj, const int N,const int bound){//will assume DP pointer is correct from host
	const int offset = blockIdx.x*blockDim.x + threadIdx.x;
	const int warp_index=threadIdx.x%32;

	__shared__ double b_val[8];
	double t_val=0.0f;

	if(offset<bound){
		int lo=0,hi=adj,cur,mid,j=offset,i;
		while(lo<hi){
			mid=(hi+lo+1)>>1;
			cur=d_choose2(mid);
			if(cur>j)hi=mid-1;
			else
				lo=mid;
		}
		j-=d_choose2(lo);
		i=lo;
		if(i>0 && (i<(N+2)) && (j<i) ){
			t_val=((double)(i)*DP[i*adj+j]);
		}
	}
	t_val+=shfl_d64(t_val,warp_index+16);
	t_val+=shfl_d64(t_val,warp_index+8);
	t_val+=shfl_d64(t_val,warp_index+4);
	t_val+=shfl_d64(t_val,warp_index+2);
	t_val+=shfl_d64(t_val,warp_index+1);
	if(warp_index==0){
		b_val[threadIdx.x>>5]=t_val;
	}
	__syncthreads();
	if(threadIdx.x==0){
		atomicAdd(&D_ans[0],(b_val[0]+b_val[1]+b_val[2]+b_val[3]+b_val[4]+b_val[5]+b_val[6]+b_val[7]));
	}
}


int main(){
	const unsigned int num_spaces=1000;
	cout<<"\nnum= "<<num_spaces<<'\n';
	const unsigned int problem_space=(num_spaces+2)*(num_spaces+2);
	const unsigned int num_bytes=problem_space*sizeof(double);
	double *DP0=(double *)malloc(num_bytes);
	double *DP1=(double *)malloc(num_bytes);
	double CPU_ans=0.,GPU_ans=0.;

	cudaError_t err=cudaDeviceReset();
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}

	UINT wTimerRes = 0;
	DWORD CPU_time=0,GPU_time=0;
    bool init = InitMMTimer(wTimerRes);
    DWORD startTime=timeGetTime();

	CPU_ans=CPU_version(DP0,DP1,num_spaces);

	DWORD endTime = timeGetTime();
    CPU_time=endTime-startTime;

    cout<<"CPU solution timing: "<<CPU_time<<'\n';
	cout<<"CPU answer= "<<CPU_ans<<'\n';

	int ii=0;
	const int adj=num_spaces+2,N=num_spaces;
	const int bound=choose2(adj);
	const double s_val=1.;

	double *D_DP0,*D_DP1,*D_ans;
	err=cudaMalloc((void**)&D_DP0, num_bytes);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaMalloc((void**)&D_DP1, num_bytes);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaMalloc((void**)&D_ans, sizeof(double));
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}

	dim3 grid0(1,1,1);

	wTimerRes = 0;
	init = InitMMTimer(wTimerRes);
	startTime = timeGetTime();

	err=cudaMemset(D_DP0,0,num_bytes);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaMemset(D_ans,0,sizeof(double));
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaMemcpy(D_DP0+adj,&s_val,sizeof(double),_HTD);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	
	for(;ii<N;ii++){
		grid0.x=( ((ii+2)+THREADS_SMALL-1)/THREADS_SMALL);
		grid0.y=(ii+1);

		if(ii&1){
			cudaMemset(D_DP0,0,num_bytes);
			GPU_step0<<<grid0,THREADS_SMALL>>>(ii,D_DP1,D_DP0,adj,N);

		}else{
			cudaMemset(D_DP1,0,num_bytes);
			GPU_step0<<<grid0,THREADS_SMALL>>>(ii,D_DP0,D_DP1,adj,N);
		}
		err=cudaThreadSynchronize();
		if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	}
	grid0.x=(bound+THREADS_LARGE-1)/THREADS_LARGE;
	grid0.y=1;
	if(N&1){
		GPU_step1<<<grid0,THREADS_LARGE>>>(D_DP1,D_ans,adj,N,bound);
	}else{
		GPU_step1<<<grid0,THREADS_LARGE>>>(D_DP0,D_ans,adj,N,bound);
	}
	err=cudaThreadSynchronize();
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}

	err=cudaMemcpy(&GPU_ans,D_ans,sizeof(double),_DTH);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}

	endTime = timeGetTime();
	GPU_time=endTime-startTime;
	cout<<"\nCUDA timing(including all memory transfers and ops): "<<GPU_time<<" , answer= "<<GPU_ans<<'\n';
	DestroyMMTimer(wTimerRes, init);


	err=cudaFree(D_DP0);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaFree(D_DP1);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	err=cudaFree(D_ans);
	if(err!=cudaSuccess){printf("%s in %s at line %d\n",cudaGetErrorString(err),__FILE__,__LINE__);}
	
	free(DP0);
	free(DP1);
	return 0;
}

bool InitMMTimer(UINT wTimerRes){
	TIMECAPS tc;
	if (timeGetDevCaps(&tc, sizeof(TIMECAPS)) != TIMERR_NOERROR) {return false;}
	wTimerRes = min(max(tc.wPeriodMin, 1), tc.wPeriodMax);
	timeBeginPeriod(wTimerRes); 
	return true;
}

void DestroyMMTimer(UINT wTimerRes, bool init){
	if(init)
		timeEndPeriod(wTimerRes);
}


