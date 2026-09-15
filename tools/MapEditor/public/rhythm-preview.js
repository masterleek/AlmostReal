// Aperçu JOUÉ d'une séquence de rythme, aux vitesses réelles de la barre.
//
// POURQUOI JOUÉ ET PAS UNE LISTE. Une suite de pastilles dit ce qu'il y a à
// TAPER, pas ce que ça fait à JOUER. Deux Ekos de trois notes n'ont pas la même
// allure — trois pressions d'affilée sur la même touche ne se jouent pas comme
// une croix, une flèche et un triangle — et rien dans une liste ne le montre.
// Même parti pris que l'aperçu de planche (cf. sheet-preview.js) : ce qui se
// juge à l'œil et à la main se regarde tourner, il ne se relit pas en chiffres.
//
// CE QUI EST FIDÈLE ET CE QUI NE L'EST PAS. Fidèles, parce que LUS dans
// RhythmBar.gd (cf. /api/battle/vocabulary) : le dessin de chaque note, la
// vitesse de défilement, l'écart entre deux arrivées, le temps de vol de la
// première et les trois fenêtres de jugement. Pas fidèles, et délibérément :
// l'habillage de la barre — sa lueur, la couleur de son camp, ses verdicts —
// qui n'est pas ce que l'auteur règle ici, et dont la copie finirait par
// diverger du jeu sans que personne s'en aperçoive.

// Côté d'une note en unités de design. Les quatre pastilles sont des SVG de
// 32 px importés à ×4 puis contre-échelonnés par PixelScale, la flèche un PNG
// de 32 px traité pareil : toutes retombent sur 32 (cf. RhythmBar._make_note).
const NOTE_SIZE = 32;
// Hauteur de la bande dessinée. La barre du jeu tient entre y = 209 et le bas
// de son anneau ; seule la hauteur compte ici, l'aperçu étant posé dans une
// page et non dans l'écran de combat.
const BAR_HEIGHT = 44;
const RING_RADIUS = 11;

// Images des notes, mises en cache par URL : la page en redessine la liste à
// chaque frappe, et chaque aperçu en réclame les mêmes huit.
const images = new Map();

function iconImage(url) {
  if (!images.has(url)) {
    images.set(url, new Promise((resolve) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => resolve(null);
      image.src = url;
    }));
  }
  return images.get(url);
}

// Le déroulé d'une séquence, calqué sur RhythmBar._build_notes : la première
// note met le temps de traverser une demi-barre, les suivantes tombent à
// intervalle fixe, et la barre reste en vie une queue de plus après la dernière.
export function sequenceTiming(sequence, timings) {
  const leadIn = timings.centre_x / timings.note_speed;
  const last = leadIn + Math.max(0, sequence.length - 1) * timings.note_interval;
  return { leadIn, last, total: sequence.length ? last + timings.tail : 0 };
}

// Les trois fenêtres de jugement en MILLISECONDES. Elles sont déclarées en
// PIXELS dans le moteur — c'est une distance à l'anneau — et c'est la vitesse
// de défilement qui les convertit en temps. Le pixel ne dit rien à personne, la
// milliseconde se compare à ce qu'on sait d'un jeu de rythme.
export function judgementWindows(timings) {
  const ms = (pixels) => Math.round((pixels / timings.note_speed) * 1000);
  return {
    perfect: ms(timings.window_perfect),
    great: ms(timings.window_great),
    good: ms(timings.window_good),
  };
}

// L'aperçu, prêt à poser dans la page : un canevas et son bouton de lecture.
// `icons` associe à chaque note son image et sa rotation (les quatre directions
// partagent un seul dessin de flèche, cf. RhythmBar.ARROW_ROTATION).
export function rhythmPreview(sequence, timings, icons) {
  const wrap = document.createElement("div");
  wrap.className = "rhythm-preview";

  const canvas = document.createElement("canvas");
  canvas.className = "rhythm-preview-canvas";
  // La largeur est celle de l'ÉCRAN DE JEU : on regarde ce que le joueur verra,
  // pas un schéma redimensionné. Le CSS la réduit si la colonne est plus
  // étroite, ce qui garde les proportions.
  const width = Math.round(timings.centre_x * 2);
  const ratio = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * ratio);
  canvas.height = Math.round(BAR_HEIGHT * ratio);
  canvas.style.width = `${width}px`;
  canvas.style.aspectRatio = `${width} / ${BAR_HEIGHT}`;
  wrap.appendChild(canvas);

  const play = document.createElement("button");
  play.type = "button";
  play.className = "text-btn rhythm-preview-play";
  play.textContent = "▶ Jouer";
  play.title = "Faire défiler la séquence à la vitesse du combat.";
  wrap.appendChild(play);

  const context = canvas.getContext("2d");
  context.scale(ratio, ratio);
  const { leadIn, total } = sequenceTiming(sequence, timings);
  const style = getComputedStyle(document.body);
  const palette = {
    track: style.getPropertyValue("--border").trim() || "#3a3f4a",
    ring: style.getPropertyValue("--accent").trim() || "#7aa2f7",
    text: style.getPropertyValue("--text").trim() || "#e6e6e6",
  };

  let loaded = null;
  const draw = (elapsed) => {
    context.clearRect(0, 0, width, BAR_HEIGHT);
    const centre = timings.centre_x;
    const middle = BAR_HEIGHT / 2;

    // Les fenêtres, de la plus large à la plus étroite : c'est une cible, et
    // c'est le seul endroit où la tolérance du jugement se VOIT.
    for (const [pixels, alpha] of [
      [timings.window_good, 0.10], [timings.window_great, 0.14],
      [timings.window_perfect, 0.30],
    ]) {
      context.globalAlpha = alpha;
      context.fillStyle = palette.ring;
      context.fillRect(centre - pixels, 2, pixels * 2, BAR_HEIGHT - 4);
    }
    context.globalAlpha = 1;

    context.strokeStyle = palette.track;
    context.lineWidth = 1;
    context.beginPath();
    context.moveTo(0, middle + 0.5);
    context.lineTo(width, middle + 0.5);
    context.stroke();

    context.strokeStyle = palette.ring;
    context.lineWidth = 2;
    context.beginPath();
    context.arc(centre, middle, RING_RADIUS, 0, Math.PI * 2);
    context.stroke();

    if (loaded === null) return;
    for (let i = 0; i < sequence.length; i++) {
      const image = loaded[i];
      // Même géométrie que RhythmBar._offset_of, côté allié : la note est à sa
      // distance de l'anneau, et les notes viennent de la DROITE.
      const time = leadIn + i * timings.note_interval;
      const x = centre + (time - elapsed) * timings.note_speed;
      if (x < -NOTE_SIZE || x > width + NOTE_SIZE) continue;
      if (image === null) {
        context.fillStyle = palette.text;
        context.font = "9px system-ui, sans-serif";
        context.textAlign = "center";
        context.textBaseline = "middle";
        context.fillText(sequence[i], x, middle);
        continue;
      }
      context.save();
      context.translate(x, middle);
      const rotation = icons[sequence[i]]?.rotation || 0;
      if (rotation) context.rotate((rotation * Math.PI) / 180);
      context.drawImage(image, -NOTE_SIZE / 2, -NOTE_SIZE / 2, NOTE_SIZE, NOTE_SIZE);
      context.restore();
    }
  };

  // AU REPOS, l'aperçu montre l'instant où la PREMIÈRE NOTE TOUCHE L'ANNEAU.
  // C'est une image réelle de l'animation — rien d'inventé — et c'est celle où
  // la séquence se lit : la note à jouer est sur la cible, les suivantes font
  // la queue derrière à leur vrai écart. À t = 0 la barre est vide, et un
  // aperçu vide ne donne pas envie d'appuyer sur « Jouer ».
  const REST = leadIn;
  draw(REST);

  Promise.all(
    sequence.map((id) => (icons[id]?.url ? iconImage(icons[id].url) : Promise.resolve(null)))
  ).then((results) => {
    loaded = results;
    if (canvas.isConnected) draw(REST);
  });

  let started = 0;
  let running = false;
  const step = (now) => {
    // La liste est reconstruite à chaque modification : un aperçu détaché du
    // document doit rendre sa boucle, sinon chaque frappe en laisse une de plus
    // à tourner dans le vide.
    if (!canvas.isConnected) return;
    const elapsed = (now - started) / 1000;
    if (elapsed >= total) {
      running = false;
      play.textContent = "▶ Jouer";
      draw(REST);
      return;
    }
    draw(elapsed);
    requestAnimationFrame(step);
  };
  play.onclick = () => {
    if (running) {
      running = false;
      play.textContent = "▶ Jouer";
      draw(REST);
      return;
    }
    if (sequence.length === 0) return;
    running = true;
    play.textContent = "■ Arrêter";
    started = performance.now();
    requestAnimationFrame(step);
  };
  play.disabled = sequence.length === 0;
  return wrap;
}
