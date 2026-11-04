const dl=document.getElementById('dl');
fetch('downloads/manifest.json').then(r=>r.ok?r.json():Promise.reject()).then(m=>{if(m.version)document.getElementById('ver').textContent='Version '+m.version}).catch(()=>{});
// Prefer the GitHub Release asset; fall back to the local copy if it is unreachable.
fetch(dl.href,{method:'HEAD',mode:'no-cors'}).catch(()=>{dl.href=dl.dataset.fallback});
if(location.search.includes("static"))document.querySelectorAll(".reveal").forEach(e=>e.classList.add("in"));
const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{threshold:.12});
document.querySelectorAll('.reveal').forEach(el=>io.observe(el));
if(location.search.includes("y="))addEventListener("load",()=>scrollTo(0,+location.search.match(/y=(\d+)/)[1]));
if(location.search.includes("zoom"))document.documentElement.style.zoom=location.search.match(/zoom=([\d.]+)/)[1];
